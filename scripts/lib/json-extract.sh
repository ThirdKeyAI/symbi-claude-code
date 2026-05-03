#!/bin/bash
# Hook payload field extraction.
#
# Claude Code delivers hook events on stdin as a JSON object. The hooks in
# this plugin only ever read a small fixed set of fields:
#   - tool_name              (string)
#   - tool_input.file_path   (string, may contain spaces)
#   - tool_input.path        (string, alternate spelling)
#   - tool_input.command     (string, may contain shell metacharacters and
#                             JSON escape sequences)
#
# Strategy, in order of preference:
#   1. jq            — preferred; correct, well-tested, handles all escapes
#   2. python3       — universal fallback; correct via stdlib json
#   3. bash regex    — last resort; narrow, refuses payloads it can't parse
#
# Functions print the extracted value (without trailing newline) to stdout
# and exit 0. Missing fields print empty and exit 0. A parse failure in the
# bash fallback exits 0 with empty output and writes a diagnostic to stderr;
# the caller treats "no value" as "no match" and proceeds safely.
#
# This file is meant to be sourced, not executed.

# Pick the best available extractor once per script run.
_SYMBI_JSON_BACKEND=""
if command -v jq >/dev/null 2>&1; then
    _SYMBI_JSON_BACKEND="jq"
elif command -v python3 >/dev/null 2>&1; then
    _SYMBI_JSON_BACKEND="python3"
elif command -v python >/dev/null 2>&1; then
    _SYMBI_JSON_BACKEND="python"
else
    _SYMBI_JSON_BACKEND="bash"
fi

# json_field <payload> <dotted.path>
# Prints the string value at the given path, or empty if absent.
json_field() {
    local payload="$1"
    local path="$2"

    case "$_SYMBI_JSON_BACKEND" in
        jq)
            printf '%s' "$payload" | jq -r --arg p "$path" '
                def walk($parts):
                    if ($parts | length) == 0 then .
                    elif type != "object" then null
                    else (.[$parts[0]] // null) | walk($parts[1:])
                    end;
                walk($p | split(".")) // empty
            ' 2>/dev/null
            ;;
        python3|python)
            printf '%s' "$payload" | "$_SYMBI_JSON_BACKEND" -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for key in sys.argv[1].split("."):
    if not isinstance(data, dict):
        sys.exit(0)
    data = data.get(key)
    if data is None:
        sys.exit(0)
if isinstance(data, str):
    sys.stdout.write(data)
elif isinstance(data, (int, float, bool)):
    sys.stdout.write(json.dumps(data))
' "$path" 2>/dev/null
            ;;
        bash)
            _json_field_bash "$payload" "$path"
            ;;
    esac
}

# Narrow bash extractor. Handles only the field shapes Claude Code emits in
# PreToolUse/PostToolUse payloads. Refuses anything more exotic by returning
# empty, which the caller treats as "field not present" — fail-open for
# logging, fail-safe for blocking (we don't block what we can't parse).
_json_field_bash() {
    local payload="$1"
    local path="$2"
    local key="${path##*.}"        # last segment is the actual field name
    local parent=""
    if [[ "$path" == *.* ]]; then
        parent="${path%.*}"        # everything before last segment
    fi

    # Narrow the search window when there's a parent object. We look for
    #   "parent": { ... }
    # and extract everything between the matching braces. Because hook
    # payloads only nest one level deep (tool_input is a flat object),
    # a single brace pair is sufficient.
    local window="$payload"
    if [ -n "$parent" ]; then
        window=$(_json_object_value "$payload" "$parent")
        [ -z "$window" ] && return 0
    fi

    _json_string_value "$window" "$key"
}

# Extract the raw object body for "key": { ... }, with nesting depth 1.
# Returns the substring including outer braces, or empty if not found.
_json_object_value() {
    local payload="$1"
    local key="$2"
    # Use awk for braces — bash regex can't match balanced delimiters.
    printf '%s' "$payload" | awk -v key="$key" '
        BEGIN { depth = 0; capturing = 0; out = "" }
        {
            line = $0
            while (length(line) > 0) {
                if (!capturing) {
                    pat = "\"" key "\"[[:space:]]*:[[:space:]]*\\{"
                    pos = match(line, pat)
                    if (pos == 0) { line = ""; continue }
                    line = substr(line, pos + RLENGTH - 1)  # start at "{"
                    capturing = 1
                    depth = 0
                }
                # Walk char-by-char tracking string state and brace depth.
                in_str = 0
                esc = 0
                for (i = 1; i <= length(line); i++) {
                    c = substr(line, i, 1)
                    out = out c
                    if (in_str) {
                        if (esc) { esc = 0 }
                        else if (c == "\\") { esc = 1 }
                        else if (c == "\"") { in_str = 0 }
                    } else {
                        if (c == "\"") { in_str = 1 }
                        else if (c == "{") { depth++ }
                        else if (c == "}") {
                            depth--
                            if (depth == 0) { print out; exit }
                        }
                    }
                }
                line = ""
            }
        }
    '
}

# Extract a JSON string value for "key": "value", honoring \" and \\ escapes.
# Returns the unescaped value or empty if not present.
_json_string_value() {
    local payload="$1"
    local key="$2"
    printf '%s' "$payload" | awk -v key="$key" '
        BEGIN { found = 0 }
        {
            line = $0
            pat = "\"" key "\"[[:space:]]*:[[:space:]]*\""
            pos = match(line, pat)
            if (pos == 0) next
            # Position scanner just past the opening quote of the value.
            i = pos + RLENGTH
            out = ""
            esc = 0
            while (i <= length(line)) {
                c = substr(line, i, 1)
                if (esc) {
                    if (c == "n") out = out "\n"
                    else if (c == "t") out = out "\t"
                    else if (c == "r") out = out "\r"
                    else if (c == "\"") out = out "\""
                    else if (c == "\\") out = out "\\"
                    else if (c == "/") out = out "/"
                    else if (c == "b") out = out "\b"
                    else if (c == "f") out = out "\f"
                    else {
                        # \uXXXX or unknown — bail out, return empty.
                        # Caller treats empty as "no value", which is safer
                        # than guessing for security-critical comparisons.
                        out = ""
                        found = 0
                        exit
                    }
                    esc = 0
                } else if (c == "\\") {
                    esc = 1
                } else if (c == "\"") {
                    found = 1
                    break
                } else {
                    out = out c
                }
                i++
            }
            if (found) { printf "%s", out; exit }
        }
        END { if (!found) exit 0 }
    '
}

# Returns the active backend name. Useful for diagnostics.
json_backend() {
    printf '%s' "$_SYMBI_JSON_BACKEND"
}
