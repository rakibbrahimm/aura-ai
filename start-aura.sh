#!/data/data/com.termux/files/usr/bin/sh

cd "$HOME/AURA-AI" || exit 1

if curl -s --max-time 1 http://127.0.0.1:8090/health >/dev/null 2>&1; then
    echo "AURA backend already running."
    exit 0
fi

nohup python api/server.py > "$HOME/AURA-AI/logs/backend.log" 2>&1 &

echo $! > "$HOME/AURA-AI/logs/backend.pid"

sleep 3

if curl -s --max-time 2 http://127.0.0.1:8090/health >/dev/null 2>&1; then
    echo "AURA backend started."
else
    echo "AURA backend failed to start."
    echo "Check: logs/backend.log"
fi
