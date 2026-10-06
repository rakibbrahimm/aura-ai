import os
import sys
import tempfile

ROOT = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__),
        ".."
    )
)

sys.path.insert(0, ROOT)

from core.local_tools import calculator
from core.security import rate_allowed
from core.billing import billing_status

assert calculator("2+3*4") == 14

assert rate_allowed(
    "test-key-fresh",
    limit=2,
    window=60
)

assert rate_allowed(
    "test-key-fresh",
    limit=2,
    window=60
)

assert rate_allowed(
    "test-key-fresh",
    limit=2,
    window=60
) is False

with tempfile.TemporaryDirectory() as d:
    x = billing_status(d)
    assert "plans" in x

print("CORE TESTS: PASS")
