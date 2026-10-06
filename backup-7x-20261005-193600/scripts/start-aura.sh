#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/AURA-AI"
mkdir -p logs

export PYTHONPATH="$HOME/AURA-AI${PYTHONPATH:+:$PYTHONPATH}"

if [ -f logs/backend.pid ]; then
 PID="$(cat logs/backend.pid 2>/dev/null || true)"
 if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  echo "AURA already running: $PID"
  exit 0
 fi
fi

nohup python "$HOME/AURA-AI/api/server.py" \
 > "$HOME/AURA-AI/logs/backend.log" 2>&1 &

PID=$!
echo "$PID" > logs/backend.pid

sleep 2

if kill -0 "$PID" 2>/dev/null; then
 echo "AURA started successfully."
 curl -s http://127.0.0.1:8090/health || true
 echo
else
 echo "AURA failed to start."
 tail -n 80 logs/backend.log || true
 exit 1
fi
