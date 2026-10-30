#!/usr/bin/env bash
# Installa l'agent SiteLink. Eseguire come root dalla cartella agent/:
#   sudo ./install.sh [file-config-modello]
# Al primo avvio copia config.example.json in /etc/sitelink/agent.json
# e genera il token; poi va editato (IP, route) e il servizio riavviato.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Esegui con sudo"; exit 1; }
command -v python3 >/dev/null || { echo "python3 mancante"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"

id sitelink >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin sitelink
install -d -m 755 /opt/sitelink
install -m 755 "$HERE/sitelink_agent.py" /opt/sitelink/sitelink_agent.py
install -m 755 "$HERE/set-peer.sh" /opt/sitelink/set-peer.sh

install -d -m 750 -o root -g sitelink /etc/sitelink
if [ ! -f /etc/sitelink/agent.json ]; then
  TOKEN="$(openssl rand -hex 32)"
  sed "s/CAMBIAMI-genera-con-openssl-rand-hex-32/$TOKEN/" "${1:-$HERE/config.example.json}" > /etc/sitelink/agent.json
  chown root:sitelink /etc/sitelink/agent.json
  chmod 640 /etc/sitelink/agent.json
  echo "Creato /etc/sitelink/agent.json (token generato). MODIFICALO prima di usarlo."
fi

if grep -q '"backend"[[:space:]]*:[[:space:]]*"command"' /etc/sitelink/agent.json; then
  # backend 'command': i comandi in config possono usare 'sudo -n' (vedi README: sudoers).
  install -d /etc/systemd/system/sitelink-agent.service.d
  printf '[Service]\nNoNewPrivileges=false\n' > /etc/systemd/system/sitelink-agent.service.d/command-backend.conf
  echo "Backend 'command': servono regole sudoers per i comandi enable/disable (vedi README)."
else
  command -v tailscale >/dev/null || { echo "tailscale mancante"; exit 1; }
  rm -f /etc/systemd/system/sitelink-agent.service.d/command-backend.conf
  # l'utente sitelink può cambiare le preferenze Tailscale senza essere root
  tailscale set --operator=sitelink
fi

install -m 644 "$HERE/sitelink-agent.service" /etc/systemd/system/sitelink-agent.service
systemctl daemon-reload
systemctl enable sitelink-agent >/dev/null
systemctl restart sitelink-agent
sleep 1
systemctl --no-pager --lines=5 status sitelink-agent || true
echo
echo "Token:  $(python3 -c "import json;print(json.load(open('/etc/sitelink/agent.json'))['token'])")"
