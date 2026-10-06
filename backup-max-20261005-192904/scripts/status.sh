#!/data/data/com.termux/files/usr/bin/sh

echo "========== AURA STATUS =========="

curl -s \
    --max-time 3 \
    http://127.0.0.1:8090/health || true

echo
echo "Version: $(cat "$HOME/AURA-AI/VERSION")"
echo "================================="
