#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/AURA-AI"

if [ ! -f logs/backend.pid ]; then
    echo "AURA is not running."
    exit 0
fi

PID="$(cat logs/backend.pid 2>/dev/null || true)"

if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    echo "AURA stopped."
else
    echo "AURA process not found."
fi

rm -f logs/backend.pid
