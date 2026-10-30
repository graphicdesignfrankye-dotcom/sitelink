#!/usr/bin/env bash
# Installa l'agent su un router via SSH, dal Mac.
# Uso: ./deploy.sh utente@host [config.example.json|config.raspberry.example.json]
# Esempi:
#   ./deploy.sh ubuntu@10.0.1.31 config.example.json
#   ./deploy.sh pi@10.0.2.2 config.raspberry.example.json
set -euo pipefail
TARGET="${1:?uso: $0 utente@host [config-modello]}"
CFG="${2:-config.example.json}"
cd "$(dirname "$0")"
REMOTE=/tmp/sitelink-agent
ssh "$TARGET" "rm -rf $REMOTE && mkdir -p $REMOTE"
scp -q sitelink_agent.py sitelink-agent.service install.sh set-peer.sh "$CFG" "$TARGET:$REMOTE/"
ssh -t "$TARGET" "cd $REMOTE && sudo ./install.sh $REMOTE/$CFG"
