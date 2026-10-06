#!/data/data/com.termux/files/usr/bin/sh

cd "$HOME/AURA-AI" || exit 1
mkdir -p logs

if curl -s --max-time 1 http://127.0.0.1:8090/health >/dev/null 2>&1; then
    echo "AURA already running."
    exit 0
fi

nohup python api/server.py >> logs/backend.log 2>&1 &
echo $! > logs/backend.pid

sleep 3

if curl -s --max-time 2 http://127.0.0.1:8090/health >/dev/null 2>&1; then
    echo "AURA backend started successfully."
else
    echo "AURA failed to start."
    tail -30 logs/backend.log
    exit 1
fi
