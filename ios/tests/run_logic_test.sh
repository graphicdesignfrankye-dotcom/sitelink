#!/usr/bin/env bash
# Prova la logica dell'app iPhone (stato, comando, peer, indirizzo alternativo) contro due agent veri in locale.
# Compila i sorgenti senza interfaccia con swiftc, quindi gira su Mac senza simulatore. Uso: tests/run_logic_test.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd)"; AG="$D/../agent"; T=$(mktemp -d)
PIDS=""; cleanup() { for p in $PIDS; do kill $p 2>/dev/null; done; }; trap cleanup EXIT
export TA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa TB=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
cat > $T/a.json <<JSON
{"site_name":"a","token":"$TA","listen":["127.0.0.1"],"port":18771,"advertise_routes":["10.0.1.0/24"],
 "remote_ping_target":"127.0.0.1","tailscale_bin":"$AG/tests/fake_tailscale.sh",
 "peer":{"url":"http://127.0.0.1:18772","token":"$TB"}}
JSON
cat > $T/b.json <<JSON
{"site_name":"b","token":"$TB","listen":["127.0.0.1"],"port":18772,"advertise_routes":["10.0.2.0/24"],
 "remote_ping_target":"127.0.0.1","backend":"command",
 "commands":{"status":["$AG/tests/fake_vpn.sh","status"],"enable":["$AG/tests/fake_vpn.sh","enable"],"disable":["$AG/tests/fake_vpn.sh","disable"]}}
JSON
export FAKE_TS_STATE=$T/ts.json
FAKE_VPN_STATE=$T/vpn python3 "$AG/sitelink_agent.py" --config $T/a.json 2>/dev/null & PIDS="$PIDS $!"
FAKE_VPN_STATE=$T/vpn python3 "$AG/sitelink_agent.py" --config $T/b.json 2>/dev/null & PIDS="$PIDS $!"
sleep 1
S="$D/SiteLink"
swiftc -parse-as-library -o $T/logic "$S/Models.swift" "$S/Keychain.swift" "$S/AgentClient.swift" "$S/LinkController.swift" "$D/tests/LogicTests.swift" 2>&1 | grep -E "error" && exit 1
$T/logic
