#!/usr/bin/env bash
# Imposta l'agent dell'altra sede in /etc/sitelink/agent.json.
#   sudo /opt/sitelink/set-peer.sh http://IP_TAILSCALE_ALTRO_ROUTER:8765
# Chiede il token dell'altro router (non viene mostrato) e riavvia il servizio.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Esegui con sudo"; exit 1; }
URL="${1:?uso: $0 http://IP:8765}"
read -r -s -p "Token dell'agent dell'altra sede: " TOK < /dev/tty; echo
PEER_URL="$URL" PEER_TOKEN="$TOK" python3 - <<'PY'
import json, os
p = "/etc/sitelink/agent.json"
c = json.load(open(p))
c["peer"] = {"url": os.environ["PEER_URL"], "token": os.environ["PEER_TOKEN"]}
json.dump(c, open(p, "w"), indent=2)
PY
chown root:sitelink /etc/sitelink/agent.json; chmod 640 /etc/sitelink/agent.json
systemctl restart sitelink-agent
echo "Peer impostato, servizio riavviato."
