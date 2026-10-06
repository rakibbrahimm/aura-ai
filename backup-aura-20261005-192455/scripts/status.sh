#!/data/data/com.termux/files/usr/bin/sh

echo "========== AURA STATUS =========="

if curl -s --max-time 2 http://127.0.0.1:8090/health; then
    echo
    echo "Backend: ONLINE"
else
    echo
    echo "Backend: OFFLINE"
fi

echo
echo "Version: $(cat "$HOME/AURA-AI/VERSION")"
echo "================================="
