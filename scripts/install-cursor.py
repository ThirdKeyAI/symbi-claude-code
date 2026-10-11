#!/usr/bin/env python3
"""Install the project hook without discarding existing hooks."""
import json
import os
from pathlib import Path
import runpy
import shlex
import sys
import tempfile

plugin = Path(__file__).resolve().parent.parent
parse_json = runpy.run_path(str(plugin / "scripts/core/policy.py"))["parse_json"]


def install():
    project = Path(sys.argv[1] if len(sys.argv) > 1 else os.getcwd()).resolve(strict=True)
    destination = project / ".cursor/hooks.json"
    original = destination.read_bytes() if destination.exists() else None
    data = parse_json(original) if original is not None else {"version": 1, "hooks": {}}
    if not isinstance(data, dict) or data.get("version", 1) != 1 or not isinstance(data.get("hooks", {}), dict):
        raise ValueError("unsupported hooks configuration")
    hooks = data.setdefault("hooks", {})
    entries = hooks.setdefault("preToolUse", [])
    if not isinstance(entries, list) or any(not isinstance(entry, dict) for entry in entries):
        raise ValueError("preToolUse must be an array of hook objects")
    guard = str(plugin / "scripts/cursor-guard.sh")
    command = "env " + shlex.quote("SYMBIONT_PROJECT_DIR=" + str(project)) + " bash " + shlex.quote(guard)
    template = parse_json((plugin / "adapters/cursor/hooks.json").read_bytes())
    entry = template["hooks"]["preToolUse"][0]
    entry["command"] = command
    hooks["preToolUse"] = [old for old in entries if guard not in old.get("command", "")] + [entry]
    data.setdefault("version", 1)
    rendered = (json.dumps(data, indent=2) + "\n").encode()
    if original == rendered:
        print(f"Already installed in {destination}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    if original is not None:
        with tempfile.NamedTemporaryFile(prefix="hooks.json.symbi-backup-", dir=destination.parent, delete=False) as backup:
            backup.write(original)
        print(f"Previous configuration saved to {backup.name}")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as stream:
            temporary = stream.name
            stream.write(rendered)
        os.replace(temporary, destination)
        temporary = None
    finally:
        if temporary:
            os.unlink(temporary)
    print(f"Installed Symbiont hook in {destination}")


if __name__ == "__main__":
    try:
        install()
    except (ValueError, OSError) as error:
        print(f"Installation failed: {error}", file=sys.stderr)
        sys.exit(1)
