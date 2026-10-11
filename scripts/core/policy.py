#!/usr/bin/env python3
"""Shared hook policy engine. Python 3.11+, standard library only."""

import datetime
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tomllib

PLUGIN_ROOT = Path(__file__).resolve().parents[2]
MAX_INPUT = 4 * 1024 * 1024
RUNTIME_TIMEOUT = 2
MAX_COMMAND = 64 * 1024


class Invalid(ValueError):
    pass


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Invalid("duplicate JSON key")
        result[key] = value
    return result


def parse_json(raw):
    return json.loads(raw, object_pairs_hook=unique_object,
                      parse_constant=lambda value: (_ for _ in ()).throw(Invalid("invalid JSON number")))


def string(value, label):
    if not isinstance(value, str) or not value.strip() or any(ord(c) < 32 for c in value):
        raise Invalid(f"{label} must be a nonempty string without control characters")
    # Reject unpaired Unicode surrogates before filesystem or runtime use.
    value.encode("utf-8", errors="strict")
    return value


def read_event():
    raw = sys.stdin.buffer.read(MAX_INPUT + 1)
    if len(raw) > MAX_INPUT:
        raise Invalid("hook input exceeds 4 MiB")
    event = parse_json(raw)
    if not isinstance(event, dict):
        raise Invalid("hook input must be an object")
    return event


def read_config(path):
    # Never wait on a FIFO/device supplied in place of a configuration file.
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise Invalid("configuration must be a regular file")
        raw = stream.read(MAX_INPUT + 1)
        if len(raw) > MAX_INPUT:
            raise Invalid("configuration exceeds 4 MiB")
        return raw


def paths_for(target, cwd):
    path = Path(string(target, "path")).expanduser()
    if not path.is_absolute():
        path = cwd / path
    # Keep the lexical spelling as well: a public symlink must not exempt a
    # secret target, nor may a secret-named link exempt a public target.
    return {str(path), os.path.abspath(path), str(path.resolve())}


def roots(event, adapter):
    cwd = Path(string(event.get("cwd", os.getcwd()), "cwd")).resolve()
    configured = os.environ.get("CLAUDE_PROJECT_DIR" if adapter in {"claude", "audit"} else "SYMBIONT_PROJECT_DIR")
    if configured:
        root = Path(configured).resolve()
    elif adapter == "cursor" and "workspace_roots" in event:
        entries = event["workspace_roots"]
        if not isinstance(entries, list) or not entries:
            raise Invalid("workspace_roots must be a nonempty array")
        candidates = [Path(string(p, "workspace root")).resolve() for p in entries]
        matches = [p for p in candidates if cwd.is_relative_to(p)]
        if matches:
            root = max(matches, key=lambda p: len(p.parts))
        elif len(candidates) == 1:
            root = candidates[0]
        else:
            raise Invalid("ambiguous workspace; install a hook for this project")
    else:
        root = cwd
    if not root.is_dir():
        raise Invalid("project directory is unavailable")
    # When a fixture/older harness omits cwd, resolve relative targets at its
    # configured project root, not at the plugin installation directory.
    return root, cwd if "cwd" in event else root


def normalize(event, adapter):
    event = dict(event)
    if adapter == "cursor" and "tool_input" not in event:
        if "command" in event:
            event.setdefault("tool_name", "Shell")
            event["tool_input"] = {"command": event["command"]}
        elif "file_path" in event:
            event.setdefault("tool_name", "Read")
            event["tool_input"] = {"file_path": event["file_path"]}
    name = string(event.get("tool_name"), "tool_name")
    args = event.get("tool_input")
    if not isinstance(args, dict):
        raise Invalid("tool_input must be an object")
    lower = name.lower().replace("_", "")
    reads = {"read", "readfile", "view", "grep", "glob", "ls", "listdirectory"}
    writes = {"write", "writefile", "edit", "editfile", "multiedit", "createfile", "deletefile", "delete", "strreplace", "applypatch", "notebookedit"}
    commands = {"bash", "shell", "runterminalcmd"}
    if lower in commands or (adapter == "cursor" and lower not in reads | writes and "command" in args):
        command = args.get("command")
        if not isinstance(command, str) or not command.strip() or "\0" in command:
            raise Invalid("command must be a nonempty string")
        if len(command) > MAX_COMMAND:
            raise Invalid("command exceeds 64 KiB")
        return event, "exec", [command]
    keys = [k for k in ("file_path", "path", "notebook_path") if k in args]
    if lower in reads | writes or (adapter == "cursor" and keys):
        action = "read" if lower in reads else "write"
        targets = [string(args[k], k) for k in keys]
        if not targets and lower in {"grep", "glob", "ls", "listdirectory"}:
            targets = ["."]
        if not targets:
            raise Invalid("file tool has no supported path field")
        return event, action, targets
    return event, "invoke", [name]


def local_policy(root):
    path = root / ".symbiont/local-policy.toml"
    if not os.path.lexists(path):
        return {"mode": {"mode": "balanced"}}
    config = tomllib.loads(read_config(path).decode("utf-8"))
    for section, values in config.items():
        allowed = {"mode": {"mode"}, "deny": {"paths", "commands", "branches"}, "allow": {"paths", "commands"}}
        if section not in allowed or not isinstance(values, dict) or values.keys() - allowed[section]:
            raise Invalid(f"unsupported policy section or key: {section}")
        if section == "mode":
            if values.get("mode") not in {"balanced", "strict", "permissive"}:
                raise Invalid("invalid policy mode")
        else:
            for key, entries in values.items():
                if not isinstance(entries, list):
                    raise Invalid(f"{section}.{key} must be an array")
                for entry in entries:
                    string(entry, f"{section}.{key} entry")
    return config


def matches(path, pattern):
    return fnmatch.fnmatchcase(path, pattern) or fnmatch.fnmatchcase(path, "*/" + pattern)


def sensitive(path, write=False):
    parts = Path(path).parts
    base = Path(path).name
    if base == ".env" or (base.startswith(".env.") and base not in {".env.test", ".env.example", ".env.sample"}):
        return True
    if set(parts) & {".ssh", ".aws", ".gcp", "gcloud", "secrets", "credentials"}:
        return True
    if base in {".npmrc", ".pypirc", ".netrc", "id_rsa", "id_ed25519", "id_ecdsa"} or base.endswith((".pem", ".key")):
        return True
    if any(path.endswith("/config/" + name) for name in ("database.yml", "credentials.json", "master.key")):
        return True
    return write and "/.github/workflows" in path and (path.endswith("/.github/workflows") or "/.github/workflows/" in path)


def control_path(path, root):
    p = Path(path)
    controls = [root / name for name in (".symbiont", "policies", ".mcp.json", "symbiont.toml", ".claude", ".cursor")]
    controls.append(PLUGIN_ROOT)
    controls.extend([Path.home() / ".claude", Path.home() / ".cursor"])
    # Resolving a directory does not resolve symlinked files within it. Include
    # the actual active configuration files, including external link targets.
    controls.extend(root / name for name in (".symbiont/local-policy.toml", ".symbiont/disabled"))
    controls.extend((root / "policies").glob("*.cedar"))
    for base in (root, Path.home()):
        controls.extend(base / name for name in (".claude/settings.json", ".claude/settings.local.json", ".claude/hooks.json", ".cursor/hooks.json"))
    controls.extend(PLUGIN_ROOT / name for name in (
        "hooks/hooks.json", "scripts/policy-guard.sh", "scripts/cursor-guard.sh",
        "scripts/core/policy.py", "adapters/cursor/hooks.json"))
    for control in controls:
        for spelling in (control, control.resolve()):
            if p == spelling or p.is_relative_to(spelling) or spelling.is_relative_to(p):
                return True
    return False


SOT = r"(?:^|[\s;(&|])"
EOT = r"(?:[\s;()&|><]|$)"
EXEC_DENIES = [
    (SOT + r"rm\s+(?:-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)\s+(?:/|/\*|~)" + EOT, "rm -rf at root or home"),
    (SOT + r"(?:mkfs[._a-zA-Z0-9]*|dd\s+if=)", "filesystem destruction command"),
    (SOT + r"chmod\s+(?:-[a-zA-Z]+\s+)*777" + EOT, "chmod 777"),
    (r":\(\)\s*\{\s*:", "fork bomb"),
]


def push_arguments(command):
    """Linear heuristic scan; never interpret or execute the shell string."""
    result = []
    for clause in re.split(r"[;&|()\n]", command):
        words = clause.split()
        for index, word in enumerate(words[:-1]):
            if word == "git" and words[index + 1] == "push":
                result.extend(words[index + 2:])
                break
    return result


def download_to_shell(command):
    pieces = command.split("|")
    return any(re.search(r"(?:curl|wget)\s", left) and
               re.match(r"\s*(?:sh|bash|zsh|fish|ksh)" + EOT, right)
               for left, right in zip(pieces, pieces[1:]))


def cedar(event, root):
    directory = root / "policies"
    if not os.path.lexists(directory):
        return
    if not directory.is_dir() or not any(directory.glob("*.cedar")):
        raise Invalid("configured policies/ must contain a Cedar policy")
    binary = shutil.which("symbi")
    if not binary:
        raise Invalid("policies/ requires a symbi runtime built with Cedar")
    result = subprocess.run([binary, "policy", "evaluate", "--stdin", "--json", "--policies", str(directory)],
                            input=json.dumps(event), text=True, capture_output=True, timeout=RUNTIME_TIMEOUT)
    if result.returncode:
        raise Invalid("Cedar evaluator failed")
    reply = parse_json(result.stdout)
    if not isinstance(reply, dict) or reply.get("tool") != event["tool_name"] or reply.get("policies_dir") != str(directory):
        raise Invalid("Cedar evaluator returned an invalid response")
    if reply.get("decision") == "deny":
        raise Invalid("Cedar policy denied this tool call")
    # The current CLI also returns success/allow for a build without Cedar or
    # an empty policy set. Only a positive evaluated-policy result is authority.
    reason = reply.get("reason")
    if reply.get("decision") != "allow" or not isinstance(reason, str) or not reason.startswith("allow policies matched: "):
        raise Invalid("Cedar evaluator did not confirm an explicit policy allow")


def decide(event, action, targets, root, cwd):
    if (root / ".symbiont/disabled").is_file():
        return "allow", ""
    policy = local_policy(root)
    mode = policy.get("mode", {}).get("mode", "balanced")
    denied, allowed = policy.get("deny", {}), policy.get("allow", {})
    warning = ""
    for target in targets:
        if action in {"read", "write"}:
            paths = paths_for(target, cwd)
            if action == "write" and any(control_path(p, root) for p in paths):
                raise Invalid("plugin control paths must be changed by the operator outside the agent session")
            for p in paths:
                if any(matches(p, pat) or pat in p for pat in denied.get("paths", [])):
                    raise Invalid("path matches a local deny rule")
                exempt = any(matches(p, pat) for pat in allowed.get("paths", []))
                if mode != "permissive" and not exempt and sensitive(p, action == "write"):
                    raise Invalid("sensitive path")
        elif action == "exec":
            if any(pat in target for pat in denied.get("commands", [])):
                raise Invalid("command matches a local deny rule")
            push_args = push_arguments(target)
            destinations = {arg.rsplit(":", 1)[-1].removeprefix("+").removeprefix("refs/heads/") for arg in push_args}
            if destinations.intersection(denied.get("branches", [])):
                raise Invalid("push to a protected branch")
            # A command exception applies to the whole command, never a harmless
            # substring of a longer command containing a denied operation.
            if mode != "permissive" and target not in allowed.get("commands", []):
                if set(push_args) & {"-f", "--force", "--force-with-lease"}:
                    raise Invalid("force push")
                if download_to_shell(target):
                    raise Invalid("download piped to shell")
                for pattern, reason in EXEC_DENIES:
                    if re.search(pattern, target):
                        raise Invalid(reason)
                if re.search(r"(?:^|[^\w])sudo(?:\s|$)", target):
                    if mode == "strict":
                        raise Invalid("sudo invocation in strict mode")
                    warning = "Symbiont notice: sudo invocation detected; use strict mode to block."
    cedar(event, root)
    return ("warn", warning) if warning else ("allow", "")


def audit(event, root, source, phase, verdict=None):
    """Local diagnostics, not a tamper-evident runtime journal. No raw arguments."""
    if (root / ".symbiont/disabled").is_file():
        return
    row = {"timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
           "tool": event.get("tool_name", "unknown"), "source": source, "phase": phase}
    if verdict:
        row["decision"] = verdict
    if isinstance(event.get("tool_use_id"), str):
        row["tool_use_id"] = event["tool_use_id"]
    row["input_sha256"] = hashlib.sha256(json.dumps(event.get("tool_input", {}), sort_keys=True).encode()).hexdigest()
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for directory in (".symbiont", "audit"):
            try:
                os.mkdir(directory, mode=0o700, dir_fd=fd)
            except FileExistsError:
                pass
            child = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        log = os.open("tool-usage.jsonl", os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=fd)
        with os.fdopen(log, "a") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                raise Invalid("diagnostic log must be a regular file with one link")
            stream.write(json.dumps(row, separators=(",", ":")) + "\n")
    finally:
        os.close(fd)


def try_audit(*args):
    try:
        audit(*args)
    except (OSError, ValueError):
        print("Symbiont: local diagnostic log could not be written", file=sys.stderr)


def session(root):
    messages = []
    if (root / ".symbiont/disabled").is_file():
        messages.append("Symbiont plugin disabled. Use /symbi:symbi-enable for operator instructions.")
    else:
        try:
            local_policy(root)
        except (OSError, ValueError) as error:
            messages.append(f"Symbiont policy configuration error: {error}; tool calls will be blocked.")
        if not (root / ".symbiont/local-policy.toml").exists() and any(sensitive(str(p)) for p in root.iterdir()):
            messages.append("Symbiont sensitive-path checks active. Use /symbi:symbi-protect to customize.")
        if (root / "policies").exists():
            messages.append("Cedar policy evaluation is required for this project; unavailable or invalid evaluation blocks calls.")
        config = root / ".mcp.json"
        binary = shutil.which("symbi")
        if binary and config.is_file():
            try:
                data = parse_json(read_config(config))
                servers = data.get("mcpServers", {})
                if not isinstance(servers, dict):
                    raise Invalid("mcpServers must be an object")
                # Keep startup below its hook deadline; verification of additional
                # servers is explicit through the verification command.
                for server in list(servers)[:3]:
                    result = subprocess.run([binary, "schemapin", "verify", "--mcp-server", string(server, "server name"), "--config", str(config)],
                                            capture_output=True, timeout=RUNTIME_TIMEOUT)
                    if result.returncode:
                        messages.append(f"MCP configuration pin not verified: {server}. Use /symbi:symbi-verify.")
                if len(servers) > 3:
                    messages.append("Additional MCP configuration pins unchecked; use /symbi:symbi-verify.")
            except (OSError, ValueError, subprocess.SubprocessError):
                messages.append("MCP configuration pin check unavailable; use /symbi:symbi-verify.")
    context = "Local hooks provide optional checks, not containment. Governed managed CLI workers do not load this plugin."
    result = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": context}}
    if messages:
        result["systemMessage"] = " | ".join(messages)
    print(json.dumps(result))


def main():
    adapter = sys.argv[1]
    if adapter == "session":
        session(Path(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())).resolve())
        return 0
    root = None
    event = {}
    try:
        if adapter == "core":
            action, target = sys.argv[2:]
            names = {"read": ("Read", "file_path"), "write": ("Write", "file_path"), "exec": ("Bash", "command"), "invoke": (target, None)}
            if action not in names:
                raise Invalid("unsupported action")
            name, key = names[action]
            event = {"tool_name": name, "tool_input": {key: target} if key else {}}
            root = Path(os.environ.get("SYMBIONT_PROJECT_DIR", os.getcwd())).resolve()
            cwd = root
            event, action, targets = normalize(event, "claude")
        else:
            event = read_event()
            root, cwd = roots(event, adapter)
            event, action, targets = normalize(event, adapter)
        if adapter == "audit":
            try_audit(event, root, "claude-code", "completed")
            return 0
        verdict, reason = decide(event, action, targets, root, cwd)
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        verdict, reason = "deny", "Blocked by Symbiont: " + str(error)
    if adapter in {"claude", "cursor"} and root is not None:
        try_audit(event, root, adapter, "decision", verdict)
    if adapter == "core":
        print(verdict + ("\t" + " ".join(reason.split()) if reason else ""))
    elif adapter == "cursor":
        if verdict == "warn":
            # preToolUse does not enforce ask. Preserve the intended human gate
            # by denying there; the dedicated shell event supports ask.
            permission = "ask" if event.get("hook_event_name") == "beforeShellExecution" else "deny"
            reason += " Review and run manually if intended."
        else:
            permission = verdict
        reply = {"permission": permission}
        if reason:
            reply.update(user_message=reason, agent_message=reason)
        print(json.dumps(reply, separators=(",", ":")))
    elif verdict == "deny":
        print(reason, file=sys.stderr)
        return 2
    elif verdict == "warn":
        print(json.dumps({"systemMessage": reason}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
