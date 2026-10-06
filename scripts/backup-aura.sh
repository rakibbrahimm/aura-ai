#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/AURA-AI"
cd "$ROOT"

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$ROOT/backups/aura-$STAMP"

mkdir -p "$DEST"

cp -a api core config connectors web scripts tests \
      VERSION RELEASE-7.0.md data "$DEST/" 2>/dev/null || true

echo "AURA BACKUP CREATED"
echo "$DEST"
