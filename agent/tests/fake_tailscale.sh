#!/usr/bin/env bash
# Finto tailscale per i test: stato in $FAKE_TS_STATE (file JSON di prefs)
S="${FAKE_TS_STATE:-/tmp/fake_ts_prefs.json}"
[ -f "$S" ] || echo '{"AdvertiseRoutes":null,"RouteAll":false}' > "$S"
case "$1" in
  status) echo '{"BackendState":"Running","TailscaleIPs":["100.64.0.1"],"Self":{"PrimaryRoutes":[]}}' ;;
  debug) cat "$S" ;;
  ip) echo 100.64.0.1 ;;
  up) ;;
  set)
    shift; adv=null; ra=false
    for a in "$@"; do
      case "$a" in
        --advertise-routes=) adv=null ;;
        --advertise-routes=*) adv="[\"${a#*=}\"]" ;;
        --accept-routes=true) ra=true ;;
      esac
    done
    echo "{\"AdvertiseRoutes\":$adv,\"RouteAll\":$ra}" > "$S" ;;
esac
