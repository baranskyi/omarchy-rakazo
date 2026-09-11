#!/usr/bin/env bash
# Everything the plugin needs to pass before it is loaded into omarchy-shell.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 tests/run_qml_tests.py

got=$(python3 -c 'print("A"*300000)' | wc -c)
capped=$(set +o pipefail; RAKAZO_BOTS_MAX_BYTES=65536 bash bin/run-capped python3 -c 'print("A"*300000)' 2>/dev/null | wc -c)
test "$capped" -le 65536
test "$got" -gt 65536
echo "run-capped ok · $capped bytes (limit 65536)"

start=$(date +%s)
RAKAZO_BOTS_MAX_SECONDS=1 bash bin/run-capped python3 -c 'import time; time.sleep(20)' >/dev/null 2>&1 || true
elapsed=$(( $(date +%s) - start ))
test "$elapsed" -lt 5
echo "run-capped deadline ok · ${elapsed}s"

if command -v omarchy >/dev/null; then
  omarchy plugin validate "$root"
  echo "omarchy plugin validate ok"
fi
