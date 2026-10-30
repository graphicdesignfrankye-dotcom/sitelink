#!/usr/bin/env bash
# Prova la logica dell'app Android (modulo core) contro due agent veri in locale. Uso: tests/run_logic_test.sh
# Serve un JDK 17 o 21 (vedi il README) e la connessione per scaricare Gradle la prima volta.
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
JDK17=$(ls -d "$HOME"/Library/Android/jdk/jdk-17*/Contents/Home 2>/dev/null | head -1)
export JAVA_HOME="${JAVA_HOME:-$JDK17}"
cd "$D" && ./gradlew :core:test --rerun-tasks --console=plain
