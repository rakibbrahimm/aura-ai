#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/AURA-AI"

echo "========================================"
echo "       AURA IMPORT PATH FIX"
echo "========================================"

echo "[1/4] Patching API import path..."

python - <<'PY'
from pathlib import Path

p = Path("api/server.py")
s = p.read_text()

old = 'import os\nimport json\nimport time\n'
new = '''import os
import sys
import json
import time

# AURA project root so core/ is importable.
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
'''

if old in s:
    s = s.replace(old, new, 1)
else:
    print("Import block already patched or changed.")

p.write_text(s)
print("API path patched.")
PY

echo "[2/4] Updating launcher..."

cat > scripts/start-aura.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/AURA-AI"
mkdir -p logs

if [ -f logs/backend.pid ]; then
    PID="$(cat logs/backend.pid 2>/dev/null || true)"

    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "AURA is already running: PID $PID"
        exit 0
    fi
fi

export PYTHONPATH="$HOME/AURA-AI${PYTHONPATH:+:$PYTHONPATH}"

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
    tail -n 50 logs/backend.log || true
    exit 1
fi
SH

chmod +x scripts/start-aura.sh

echo "[3/4] Validating..."
python -m py_compile api/server.py
python -m py_compile core/memory.py
python -m py_compile core/local_tools.py

echo "Syntax: OK"

echo "[4/4] Starting AURA..."

if [ -f logs/backend.pid ]; then
    OLD_PID="$(cat logs/backend.pid 2>/dev/null || true)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null || true
        sleep 1
    fi
fi

rm -f logs/backend.pid

./scripts/start-aura.sh

sleep 2

echo
echo "========== FINAL HEALTH =========="
curl -s http://127.0.0.1:8090/health
echo

echo
echo "========================================"
echo "       AURA IMPORT FIX COMPLETE"
echo "========================================"
