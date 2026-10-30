#!/usr/bin/env bash
# Finta VPN per i test del backend 'command'. Stato nel file $FAKE_VPN_STATE.
S="${FAKE_VPN_STATE:-/tmp/fake_vpn_state}"
case "$1" in
  status) [ -f "$S" ] ;;
  enable) touch "$S" ;;
  disable) rm -f "$S" ;;
  fail) echo "errore simulato" >&2; exit 3 ;;
esac
