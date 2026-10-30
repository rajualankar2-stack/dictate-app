#!/bin/bash
# One-time setup: create .venv in this clone (the app's default Python) with the speech engine (parakeet-mlx) and
# pre-download the Parakeet model (about 2.5 GB, once), so the first key press does not wait on it.
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
.venv/bin/python -m pip install --quiet numpy==2.4.6 soundfile==0.14.0 scipy==1.17.1 parakeet-mlx

echo "downloading the Parakeet model (about 2.5 GB, once)..."
.venv/bin/python -c "from parakeet_mlx import from_pretrained; from_pretrained('mlx-community/parakeet-tdt-0.6b-v3')"

echo "setup done: $PWD/.venv/bin/python"
