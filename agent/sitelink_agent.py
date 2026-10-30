#!/usr/bin/env python3
"""SiteLink agent: piccola API HTTP per accendere/spegnere il collegamento
site-to-site su un router. Solo libreria standard.

Il collegamento è gestito da un backend configurabile:
  "tailscale" (default)  tailscale set --advertise-routes / --accept-routes
  "command"              tre comandi fissi definiti in config (stato/accendi/spegni),
                         per qualsiasi altra VPN (WireGuard, OpenVPN, ...)

Azioni consentite (nessun comando arbitrario dal client):
  GET  /health   -> senza token, solo "ok"
  GET  /status   -> stato VPN, route, ping verso l'altra sede
  POST /enable   -> accende il collegamento
  POST /disable  -> spegne il collegamento
  GET /peer/status, POST /peer/enable, POST /peer/disable
                 -> inoltrano la stessa azione all'agent dell'altra sede
                    (indirizzo fisso in config)
Tutte le altre richieste richiedono "Authorization: Bearer <token>".
"""
import argparse
import hmac
import json
import logging
import os
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

API_VERSION = 2
DEFAULT_CONFIG = "/etc/sitelink/agent.json"
IP_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")
CIDR_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$")
PEER_URL_RE = re.compile(r"^http://\d{1,3}(\.\d{1,3}){3}:\d{1,5}$")
HOST_RE = re.compile(r"^[A-Za-z0-9.\-]{1,253}$")
IFACE_RE = re.compile(r"^iface:[A-Za-z0-9_.\-]{1,15}$")
COMMAND_ACTIONS = ("status", "enable", "disable")

log = logging.getLogger("sitelink")
_action_lock = threading.Lock()


def load_config(path):
    with open(path) as f:
        cfg = json.load(f)
    required = ["site_name", "token", "listen", "port", "advertise_routes", "remote_ping_target"]
    missing = [k for k in required if k not in cfg]
    if missing:
        raise ValueError("config: mancano le chiavi %s" % ", ".join(missing))
    if len(cfg["token"]) < 24 or cfg["token"].startswith("CAMBIAMI"):
        raise ValueError("config: token troppo corto o non impostato (min 24 caratteri)")
    for r in cfg["advertise_routes"]:
        if not CIDR_RE.match(r):
            raise ValueError("config: route non valida %r" % r)
    for entry in cfg["listen"]:
        if not (IP_RE.match(entry) or entry == "tailscale" or IFACE_RE.match(entry)):
            raise ValueError("config: 'listen' non valido %r (IP, 'tailscale' o 'iface:NOME')" % entry)
    if not HOST_RE.match(cfg["remote_ping_target"]):
        raise ValueError("config: remote_ping_target non valido")
    peer = cfg.get("peer")
    if peer is not None:
        if not PEER_URL_RE.match(peer.get("url", "")) or len(peer.get("token", "")) < 24:
            raise ValueError("config: 'peer' richiede url (http://IP:porta) e token")
    cfg.setdefault("backend", "tailscale")
    if cfg["backend"] not in ("tailscale", "command"):
        raise ValueError("config: backend deve essere 'tailscale' o 'command'")
    if cfg["backend"] == "command":
        cmds = cfg.get("commands") or {}
        for a in COMMAND_ACTIONS:
            c = cmds.get(a)
            if not (isinstance(c, list) and c and all(isinstance(x, str) and x for x in c)):
                raise ValueError("config: commands.%s deve essere una lista di argomenti" % a)
    cfg.setdefault("tailscale_bin", "tailscale")
    cfg.setdefault("ip_bin", "ip")
    cfg.setdefault("ping_bin", "ping")
    cfg.setdefault("command_timeout", 15)
    return cfg


def run(cmd, timeout):
    """Esegue un comando fisso (lista, mai shell). Ritorna (rc, stdout, stderr)."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"
    except FileNotFoundError:
        return 127, "", "comando non trovato: %s" % cmd[0]


class TailscaleBackend:
    kind = "tailscale"

    def __init__(self, cfg):
        self.cfg = cfg
        self.ts = cfg["tailscale_bin"]
        self.to = cfg["command_timeout"]

    def _status(self):
        rc, out, err = run([self.ts, "status", "--json"], self.to)
        if rc != 0 and not out:
            return {"up": False, "state": "Unavailable", "error": err}
        try:
            data = json.loads(out)
        except ValueError:
            return {"up": False, "state": "Unknown", "error": "output non valido"}
        state = data.get("BackendState", "Unknown")
        self_node = data.get("Self") or {}
        return {
            "up": state == "Running",
            "state": state,
            "ips": data.get("TailscaleIPs") or [],
            "primary_routes": self_node.get("PrimaryRoutes") or [],
        }

    def _prefs(self):
        rc, out, _ = run([self.ts, "debug", "prefs"], self.to)
        if rc != 0:
            return {}
        try:
            return json.loads(out)
        except ValueError:
            return {}

    def info(self):
        vpn = self._status()
        prefs = self._prefs()
        advertised = prefs.get("AdvertiseRoutes") or []
        accept = bool(prefs.get("RouteAll"))
        wanted = self.cfg["advertise_routes"]
        link_on = vpn["up"] and sorted(advertised) == sorted(wanted) and accept
        return {"up": vpn["up"], "link_enabled": link_on, "vpn": vpn,
                "advertised_routes": advertised, "accept_routes": accept}

    def set_link(self, enabled):
        """Argomenti costruiti solo dalla config, mai dal client."""
        if enabled:
            args = ["--advertise-routes=" + ",".join(self.cfg["advertise_routes"]),
                    "--accept-routes=true"]
        else:
            args = ["--advertise-routes=", "--accept-routes=false"]
        rc, _, err = run([self.ts, "set"] + args, self.to)
        if rc != 0:
            raise RuntimeError(err or "tailscale set fallito (rc=%d)" % rc)
        if enabled and not self._status()["up"]:
            rc, _, err = run([self.ts, "up"], self.to)
            if rc != 0:
                raise RuntimeError(err or "tailscale up fallito")


class CommandBackend:
    """Tre comandi fissi dalla config. 'status': codice 0 = collegamento acceso."""
    kind = "command"

    def __init__(self, cfg):
        self.cfg = cfg
        self.cmds = cfg["commands"]
        self.to = cfg["command_timeout"]

    def info(self):
        rc, _, _ = run(self.cmds["status"], self.to)
        up = rc == 0
        wanted = self.cfg["advertise_routes"]
        return {"up": up, "link_enabled": up, "vpn": {"up": up},
                "advertised_routes": wanted if up else [], "accept_routes": up}

    def set_link(self, enabled):
        rc, _, err = run(self.cmds["enable" if enabled else "disable"], self.to)
        if rc != 0:
            raise RuntimeError(err or "comando %s fallito (rc=%d)" % ("enable" if enabled else "disable", rc))


class Agent:
    def __init__(self, cfg):
        self.cfg = cfg
        self.vpn = CommandBackend(cfg) if cfg["backend"] == "command" else TailscaleBackend(cfg)

    def ping(self):
        target = self.cfg["remote_ping_target"]
        t0 = time.time()
        rc, out, _ = run([self.cfg["ping_bin"], "-c", "1", "-W", "2", target], 5)
        ms = None
        m = re.search(r"time[=<]([\d.]+)", out)
        if m:
            ms = float(m.group(1))
        return {"target": target, "reachable": rc == 0, "rtt_ms": ms,
                "checked_in_s": round(time.time() - t0, 2)}

    def status(self):
        i = self.vpn.info()
        vpn = dict(i["vpn"], type=self.vpn.kind)
        return {
            "api_version": API_VERSION,
            "site": self.cfg["site_name"],
            "link_enabled": i["link_enabled"],
            "vpn": vpn,
            "advertised_routes": i["advertised_routes"],
            "accept_routes": i["accept_routes"],
            "expected_routes": self.cfg["advertise_routes"],
            "ping": self.ping() if i["up"] else {"target": self.cfg["remote_ping_target"],
                                                  "reachable": False, "rtt_ms": None},
            "time": int(time.time()),
        }

    def set_link(self, enabled):
        self.vpn.set_link(enabled)


def peer_call(cfg, action, method):
    """Inoltra un'azione predefinita all'agent dell'altra sede. Ritorna (codice, dict)."""
    peer = cfg.get("peer")
    if not peer:
        return 501, {"error": "peer non configurato"}
    req = urllib.request.Request(peer["url"] + "/" + action, method=method,
                                 headers={"Authorization": "Bearer " + peer["token"]})
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            return 200, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return 502, {"error": "altra sede: HTTP %d" % e.code}
    except (urllib.error.URLError, OSError, ValueError) as e:
        return 502, {"error": "altra sede non raggiungibile: %s" % getattr(e, "reason", e)}


def make_handler(cfg, agent):
    token = cfg["token"].encode()

    class Handler(BaseHTTPRequestHandler):
        server_version = "SiteLink"
        sys_version = ""

        def log_message(self, fmt, *args):
            log.info("%s %s", self.address_string(), fmt % args)

        def _send(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _authed(self):
            h = self.headers.get("Authorization", "")
            if h.startswith("Bearer ") and hmac.compare_digest(h[7:].encode(), token):
                return True
            time.sleep(0.5)  # frena il brute-force
            self._send(401, {"error": "non autorizzato"})
            return False

        def do_GET(self):
            if self.path == "/health":
                return self._send(200, {"ok": True, "api_version": API_VERSION})
            if self.path == "/status":
                if self._authed():
                    self._send(200, agent.status())
                return
            if self.path == "/peer/status":
                if self._authed():
                    self._send(*peer_call(cfg, "status", "GET"))
                return
            self._send(404, {"error": "non trovato"})

        def do_POST(self):
            if self.path in ("/peer/enable", "/peer/disable"):
                if self._authed():
                    with _action_lock:
                        self._send(*peer_call(cfg, self.path.split("/")[2], "POST"))
                return
            if self.path not in ("/enable", "/disable"):
                return self._send(404, {"error": "non trovato"})
            if not self._authed():
                return
            enabled = self.path == "/enable"
            with _action_lock:
                try:
                    agent.set_link(enabled)
                except RuntimeError as e:
                    log.error("azione %s fallita: %s", self.path, e)
                    return self._send(500, {"error": str(e)})
            log.info("collegamento %s", "ATTIVATO" if enabled else "DISATTIVATO")
            self._send(200, agent.status())

    return Handler


def resolve_listen(cfg):
    """IP letterale; 'tailscale' -> IPv4 Tailscale; 'iface:NOME' -> IPv4 dell'interfaccia."""
    to = cfg["command_timeout"]
    ips = []
    for e in cfg["listen"]:
        ip = None
        if e == "tailscale":
            rc, out, _ = run([cfg["tailscale_bin"], "ip", "-4"], to)
            ip = out.split()[0] if rc == 0 and out.split() else None
        elif e.startswith("iface:"):
            rc, out, _ = run([cfg["ip_bin"], "-4", "-o", "addr", "show", "dev", e[6:]], to)
            m = re.search(r"inet (\d{1,3}(?:\.\d{1,3}){3})/", out) if rc == 0 else None
            ip = m.group(1) if m else None
        else:
            ip = e
        if ip:
            ips.append(ip)
    return ips


def serve(cfg):
    agent = Agent(cfg)
    handler = make_handler(cfg, agent)
    servers = {}

    def try_bind():
        for ip in resolve_listen(cfg):
            if ip in servers:
                continue
            try:
                srv = ThreadingHTTPServer((ip, cfg["port"]), handler)
            except OSError as e:
                log.warning("bind %s:%s fallito: %s", ip, cfg["port"], e)
                continue
            servers[ip] = srv
            threading.Thread(target=srv.serve_forever, daemon=True).start()
            log.info("in ascolto su %s:%s", ip, cfg["port"])

    log.info("backend: %s", cfg["backend"])
    try_bind()
    if not servers:
        log.error("nessun indirizzo di ascolto disponibile, riprovo")
    while True:  # ricontrolla: l'IP della VPN compare solo dopo che il servizio è su
        time.sleep(30)
        try_bind()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=os.environ.get("SITELINK_CONFIG", DEFAULT_CONFIG))
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        cfg = load_config(args.config)
    except (OSError, ValueError) as e:
        log.error("%s", e)
        sys.exit(2)
    serve(cfg)


if __name__ == "__main__":
    main()
