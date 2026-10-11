#!/bin/bash
set -eu
ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -I "$ADAPTER_DIR/../../scripts/install-cursor.py" "${1:-$PWD}"
