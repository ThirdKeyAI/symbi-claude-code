#!/bin/bash
# Wire the Cursor adapter into a project's .cursor/hooks.json.
#
#   Usage: adapters/cursor/install.sh [project-dir]   (default: $PWD)
#
# Cursor has no plugin manager, so the hook command needs an absolute path
# to this checkout. We substitute it into the template rather than asking
# the user to hand-edit JSON.

set -uo pipefail

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYMBI_ROOT="$(cd "${ADAPTER_DIR}/../.." && pwd)"
TARGET="${1:-$PWD}"
HOOKS="${TARGET}/.cursor/hooks.json"

template=$(cat "${ADAPTER_DIR}/hooks.json")
# Bash substitution, not sed: the checkout path may contain any sed delimiter.
rendered="${template//__SYMBI_ROOT__/$SYMBI_ROOT}"

if [ ! -f "$HOOKS" ]; then
    mkdir -p "${TARGET}/.cursor"
    printf '%s\n' "$rendered" > "$HOOKS"
    echo "Installed Symbiont Cursor hook -> $HOOKS"
    exit 0
fi

if grep -q 'cursor-guard.sh' "$HOOKS"; then
    echo "Already installed in $HOOKS — nothing to do."
    exit 0
fi

# An existing hooks.json is the user's file. Merge, never clobber.
if command -v jq >/dev/null 2>&1; then
    backup="${HOOKS}.symbi-backup"
    cp "$HOOKS" "$backup"
    entry=$(printf '%s' "$rendered" | jq '.hooks.preToolUse[0]')
    if jq --argjson e "$entry" \
        '.version = (.version // 1)
         | .hooks = (.hooks // {})
         | .hooks.preToolUse = ((.hooks.preToolUse // []) + [$e])' \
        "$backup" > "$HOOKS"; then
        echo "Merged Symbiont Cursor hook into $HOOKS (backup: $backup)"
        exit 0
    fi
    # jq failed — restore rather than leave a half-written config.
    cp "$backup" "$HOOKS"
    echo "Merge failed; $HOOKS left unchanged." >&2
fi

cat >&2 <<EOF
$HOOKS already exists and jq is not available to merge it safely.
Add this entry to .hooks.preToolUse yourself:

$(printf '%s' "$rendered" | sed -n '/"preToolUse"/,/]/p')
EOF
exit 1
