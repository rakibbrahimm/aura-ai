#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/AURA-AI"

if [ -f logs/backend.pid ]; then
 PID="$(cat logs/backend.pid 2>/dev/null || true)"

 if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  kill "$PID" 2>/dev/null || true
  sleep 1
 fi

 rm -f logs/backend.pid
fi

echo "AURA stopped."
