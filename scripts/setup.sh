#!/bin/bash
# One-time setup: create .venv in this clone (the app's default Python) with the audio packages the servers need.
# The speech model itself comes from the HEX app (brew install --cask anomalyco/tap/hex).
set -euo pipefail
cd "$(dirname "$0")/.."

PY=""
for c in python3.11 python3.12 python3.13 python3.10 python3; do
  if command -v "$c" >/dev/null && "$c" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then PY=$(command -v "$c"); break; fi
done
[ -n "$PY" ] || { echo "Need Python 3.10+ (macOS ships 3.9). Install it with: brew install python@3.11"; exit 1; }
echo "using $PY ($("$PY" --version))"

[ -x .venv/bin/python ] || "$PY" -m venv .venv
.venv/bin/python -m pip install --quiet --upgrade pip
# Versions the app was tested with.
.venv/bin/python -m pip install --quiet numpy==2.4.6 soundfile==0.14.0 scipy==1.17.1

echo "setup done: $PWD/.venv/bin/python"
