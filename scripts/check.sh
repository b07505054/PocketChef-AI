#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "Checking Python syntax..."
python3 -m py_compile dashboard/server.py scripts/*.py
echo "OK: Python syntax check passed."
