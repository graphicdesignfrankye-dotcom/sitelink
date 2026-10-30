#!/usr/bin/env bash
# Autorizza SENZA password solo i comandi 'route add/delete' esatti per le reti
# della tua config (una volta sola, serve la password admin).
#   sudo ./install-routes.sh [percorso-config]
# Da rieseguire se cambi subnet o gateway nella config.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Esegui con: sudo $0"; exit 1; }
U="${SUDO_USER:?esegui con sudo da utente normale}"
CFG="${1:-$(eval echo "~$U")/Library/Application Support/SiteLink/config.json}"
[ -f "$CFG" ] || { echo "Config non trovata: $CFG"; exit 1; }
TMP="$(mktemp)"
python3 - "$CFG" "$U" > "$TMP" <<'PY'
import json, re, sys
cfg = json.load(open(sys.argv[1])); user = sys.argv[2]
ip = r"^\d{1,3}(\.\d{1,3}){3}$"; net = ip[:-1] + r"/\d{1,2}$"
a, b = cfg["sites"]
cmds = []
for here, there in ((a, b), (b, a)):   # sono nella sede 'here', raggiungo 'there'
    assert re.match(net, there["subnet"]) and re.match(ip, here["gateway"]), "config non valida"
    for verb in ("add", "delete"):
        cmds.append("/sbin/route -n %s -net %s %s" % (verb, there["subnet"], here["gateway"]))
print("# generato da SiteLink install-routes.sh")
print("%s ALL=(root) NOPASSWD: %s" % (user, ", ".join(cmds)))
PY
visudo -cf "$TMP"
install -m 440 -o root -g wheel "$TMP" /etc/sudoers.d/sitelink
rm -f "$TMP"
echo "Installato /etc/sudoers.d/sitelink:"; cat /etc/sudoers.d/sitelink
