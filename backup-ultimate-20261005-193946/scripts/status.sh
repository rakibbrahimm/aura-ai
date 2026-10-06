#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/AURA-AI"

echo "================================================"
echo "                 AURA AI 7.0"
echo "================================================"

curl -s http://127.0.0.1:8090/health || true
echo

if [ -f logs/backend.pid ]; then
 PID="$(cat logs/backend.pid 2>/dev/null || true)"

 if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  echo "Backend: ONLINE"
  echo "PID: $PID"
 else
  echo "Backend: OFFLINE"
 fi
else
 echo "Backend: OFFLINE"
fi

echo "Version: $(cat VERSION 2>/dev/null || echo unknown)"
echo "================================================"
