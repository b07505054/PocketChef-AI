#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

VENV_PYTHON=".venv/bin/python"

if [ ! -x "$VENV_PYTHON" ]; then
  echo "ERROR: $VENV_PYTHON not found." >&2
  echo "Create it with: python3.11 -m venv .venv" >&2
  exit 1
fi

echo "Checking Python syntax..."
"$VENV_PYTHON" -m py_compile dashboard/server.py scripts/*.py
echo "OK: Python syntax check passed."
