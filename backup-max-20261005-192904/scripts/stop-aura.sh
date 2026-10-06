#!/data/data/com.termux/files/usr/bin/sh

PID_FILE="$HOME/AURA-AI/logs/backend.pid"

if [ -f "$PID_FILE" ]; then
    PID="$(cat "$PID_FILE")"
    kill "$PID" 2>/dev/null || true
    rm -f "$PID_FILE"
fi

echo "AURA stopped."
