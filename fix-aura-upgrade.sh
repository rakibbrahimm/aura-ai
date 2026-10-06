#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "========================================"
echo "       AURA AI RECOVERY + FIX"
echo "========================================"

cd "$HOME/AURA-AI"

# Find latest backup
BACKUP="$(ls -dt backup-aura-* 2>/dev/null | head -n 1 || true)"

if [ -z "$BACKUP" ]; then
    echo "ERROR: No AURA backup found."
    exit 1
fi

echo "[1/6] Using backup: $BACKUP"

# Stop current backend if running
if [ -f logs/backend.pid ]; then
    PID="$(cat logs/backend.pid 2>/dev/null || true)"
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        sleep 1
    fi
fi

echo "[2/6] Restoring known-good API server..."
if [ -f "$BACKUP/api/server.py" ]; then
    cp "$BACKUP/api/server.py" api/server.py
else
    echo "ERROR: Backup does not contain api/server.py"
    exit 1
fi

echo "[3/6] Python syntax check..."
python -m py_compile api/server.py

echo "[4/6] Starting AURA..."
chmod +x scripts/start-aura.sh 2>/dev/null || true
chmod +x scripts/start.sh 2>/dev/null || true

if [ -f scripts/start-aura.sh ]; then
    ./scripts/start-aura.sh
elif [ -f scripts/start.sh ]; then
    ./scripts/start.sh
else
    echo "ERROR: No start script found."
    exit 1
fi

sleep 2

echo "[5/6] Health check..."
if command -v curl >/dev/null 2>&1; then
    curl -s http://127.0.0.1:8090/health || true
    echo
else
    python - <<'PY'
import urllib.request
try:
    print(urllib.request.urlopen("http://127.0.0.1:8090/health", timeout=5).read().decode())
except Exception as e:
    print("Health check:", e)
PY
fi

echo "[6/6] Final status..."
if [ -f scripts/status.sh ]; then
    ./scripts/status.sh || true
fi

echo
echo "========================================"
echo " AURA RECOVERED"
echo "========================================"
echo "Broken server.py was restored from:"
echo "$BACKUP/api/server.py"
echo
echo "The new local upgrade files remain."
echo "========================================"
