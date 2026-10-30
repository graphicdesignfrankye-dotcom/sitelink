#!/usr/bin/env bash
# Prova l'agent in locale (finto tailscale, finta VPN, due agent collegati). Uso: tests/run_local_test.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd)"; T=$(mktemp -d)
FAIL=0; PIDS=""
cleanup() { for p in $PIDS; do kill $p 2>/dev/null; done; }; trap cleanup EXIT
check() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (atteso '$3', ottenuto '$2')"; FAIL=1; fi; }
field() { python3 -c "import sys,json;d=json.load(sys.stdin);print(eval(sys.argv[1]))" "$1"; }
TA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; TB=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; TC=cccccccccccccccccccccccccccccccc

# A: backend tailscale (finto), con peer verso B. B: backend command (finto).
cat > $T/a.json <<JSON
{"site_name":"a","token":"$TA","listen":["127.0.0.1"],"port":18771,"advertise_routes":["10.0.1.0/24"],
 "remote_ping_target":"127.0.0.1","tailscale_bin":"$D/tests/fake_tailscale.sh",
 "peer":{"url":"http://127.0.0.1:18772","token":"$TB"}}
JSON
cat > $T/b.json <<JSON
{"site_name":"b","token":"$TB","listen":["127.0.0.1"],"port":18772,"advertise_routes":["10.0.2.0/24"],
 "remote_ping_target":"127.0.0.1","backend":"command",
 "commands":{"status":["$D/tests/fake_vpn.sh","status"],"enable":["$D/tests/fake_vpn.sh","enable"],"disable":["$D/tests/fake_vpn.sh","disable"]}}
JSON
cat > $T/c.json <<JSON
{"site_name":"c","token":"$TC","listen":["127.0.0.1"],"port":18773,"advertise_routes":["10.0.0.0/24"],
 "remote_ping_target":"127.0.0.1","backend":"command",
 "commands":{"status":["$D/tests/fake_vpn.sh","status"],"enable":["$D/tests/fake_vpn.sh","fail"],"disable":["$D/tests/fake_vpn.sh","disable"]}}
JSON
export FAKE_TS_STATE=$T/ts.json
FAKE_VPN_STATE=$T/vpn python3 "$D/sitelink_agent.py" --config $T/a.json 2>/dev/null & PIDS="$PIDS $!"
FAKE_VPN_STATE=$T/vpn python3 "$D/sitelink_agent.py" --config $T/b.json 2>/dev/null & PIDS="$PIDS $!"
FAKE_VPN_STATE=$T/vpn2 python3 "$D/sitelink_agent.py" --config $T/c.json 2>/dev/null & PIDS="$PIDS $!"
sleep 1
A="Authorization: Bearer $TA"; B="Authorization: Bearer $TB"; C="Authorization: Bearer $TC"

echo "Base"
check "health" "$(curl -s localhost:18771/health | field "d['ok']")" "True"
check "401 senza token" "$(curl -s -o /dev/null -w '%{http_code}' localhost:18771/status)" "401"
check "404 path inventato" "$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "$A" localhost:18771/exec)" "404"

echo "Backend tailscale"
check "enable"  "$(curl -s -X POST -H "$A" localhost:18771/enable | field "d['link_enabled'],d['vpn']['type'],d['advertised_routes']")" "(True, 'tailscale', ['10.0.1.0/24'])"
check "api_version" "$(curl -s -H "$A" localhost:18771/status | field "d['api_version']")" "2"
check "disable" "$(curl -s -X POST -H "$A" localhost:18771/disable | field "d['link_enabled'],d['advertised_routes']")" "(False, [])"

echo "Backend command"
check "stato iniziale spento" "$(curl -s -H "$B" localhost:18772/status | field "d['link_enabled'],d['vpn']['type']")" "(False, 'command')"
check "enable"  "$(curl -s -X POST -H "$B" localhost:18772/enable | field "d['link_enabled'],d['advertised_routes']")" "(True, ['10.0.2.0/24'])"
check "disable" "$(curl -s -X POST -H "$B" localhost:18772/disable | field "d['link_enabled']")" "False"
check "comando fallito -> 500" "$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "$C" localhost:18773/enable)" "500"

echo "Peer (A inoltra a B)"
check "peer enable"  "$(curl -s -X POST -H "$A" localhost:18771/peer/enable | field "d['site'],d['link_enabled']")" "('b', True)"
check "peer status"  "$(curl -s -H "$A" localhost:18771/peer/status | field "d['link_enabled']")" "True"
check "peer disable" "$(curl -s -X POST -H "$A" localhost:18771/peer/disable | field "d['link_enabled']")" "False"
check "peer non configurato -> 501" "$(curl -s -o /dev/null -w '%{http_code}' -H "$B" localhost:18772/peer/status)" "501"

echo "Config non valida"
echo '{"site_name":"x","token":"short","listen":["127.0.0.1"],"port":1,"advertise_routes":[],"remote_ping_target":"x"}' > $T/bad.json
python3 "$D/sitelink_agent.py" --config $T/bad.json >/dev/null 2>&1; check "token corto rifiutato (exit 2)" "$?" "2"
echo '{"site_name":"x","token":"dddddddddddddddddddddddddddddddd","listen":["127.0.0.1"],"port":1,"advertise_routes":[],"remote_ping_target":"x","backend":"command"}' > $T/bad2.json
python3 "$D/sitelink_agent.py" --config $T/bad2.json >/dev/null 2>&1; check "backend command senza comandi (exit 2)" "$?" "2"

[ $FAIL -eq 0 ] && echo "TUTTO OK" || { echo "ALCUNI TEST FALLITI"; exit 1; }
