#!/bin/bash
# Compatibility entrypoint: action + target -> allow / warn<TAB>reason / deny<TAB>reason.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || { printf 'deny\tEngine unavailable\n'; exit 0; }
python3 -I "$SCRIPT_DIR/policy.py" core "$@" && exit 0
printf 'deny\tSymbiont policy engine unavailable; Python 3.11+ is required.\n'
exit 0
