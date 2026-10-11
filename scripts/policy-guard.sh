#!/bin/bash
# Stable hook entrypoint; policy and parsing live in the shared engine.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
python3 -I "$SCRIPT_DIR/core/policy.py" claude
rc=$?
[ "$rc" -eq 0 ] && exit 0
[ "$rc" -eq 2 ] && exit 2
printf '%s\n' "Symbiont policy engine unavailable; Python 3.11+ is required." >&2
exit 2
