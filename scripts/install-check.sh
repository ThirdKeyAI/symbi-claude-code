#!/bin/bash
# Stable hook entrypoint; policy and parsing live in the shared engine.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
python3 -I "$SCRIPT_DIR/core/policy.py" session
rc=$?
[ "$rc" -eq 0 ] && exit 0
printf '%s\n' '{"systemMessage":"Symbiont requires Python 3.11+; policy hooks will block until it is available."}'
exit 0
