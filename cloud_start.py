import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
os.chdir(ROOT)
sys.path.insert(0, ROOT)

# Cloud hosting supplies PORT.
# Local Termux continues using 8090.
os.environ.setdefault("AURA_HOST", "0.0.0.0")
os.environ.setdefault("AURA_PORT", os.environ.get("PORT", "8090"))

from api.server import main

if __name__ == "__main__":
    main()
