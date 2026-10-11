#!/usr/bin/env python3
"""Exercise the real policy CLI through shipping hooks, without a model call.

Usage: python3 -I tests/runtime_e2e.py /absolute/path/to/symbi
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

plugin = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve(strict=True)
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    (root / "bin").mkdir()
    (root / "bin/symbi").symlink_to(binary)
    (root / "policies").mkdir()
    policy = root / "policies/main.cedar"
    env = dict(os.environ, PATH=str(root / "bin") + os.pathsep + os.environ["PATH"],
               CLAUDE_PROJECT_DIR=str(root), SYMBIONT_PROJECT_DIR=str(root))
    policy.write_text('''permit(principal, action, resource);
forbid(principal, action, resource) when {
  action == Symbi::Action::"tool_call::Read" && context.tool_input.file_path == "blocked.txt"
};
forbid(principal, action, resource) when {
  action == Symbi::Action::"tool_call::Shell" && context.tool_input.command == "blocked command"
};
forbid(principal, action, resource) when {
  action == Symbi::Action::"tool_call::mcp__example__lookup" && context.tool_input.options.level == "restricted"
};
''')
    cases = [
        ("policy-guard.sh", "Read", {"file_path": "blocked.txt"}, False),
        ("policy-guard.sh", "Read", {"file_path": "source.txt"}, True),
        ("policy-guard.sh", "mcp__example__lookup", {"options": {"level": "restricted"}}, False),
        ("policy-guard.sh", "mcp__example__lookup", {"options": {"level": "public"}}, True),
        ("cursor-guard.sh", "Shell", {"command": "blocked command"}, False),
        ("cursor-guard.sh", "Shell", {"command": "printf harmless"}, True),
    ]
    for script, tool, args, want in cases:
        result = subprocess.run(["bash", str(plugin / "scripts" / script)], env=env, capture_output=True, text=True,
                                input=json.dumps({"tool_name": tool, "tool_input": args}))
        allowed = json.loads(result.stdout)["permission"] == "allow" if script == "cursor-guard.sh" else result.returncode == 0
        assert allowed == want, (script, tool, result.returncode, result.stdout, result.stderr)
        print(f"PASS real runtime {script} {tool}: {'allow' if want else 'deny'}")
    policy.write_text("this is invalid Cedar;")
    result = subprocess.run(["bash", str(plugin / "scripts/policy-guard.sh")], env=env, capture_output=True, text=True,
                            input=json.dumps({"tool_name": "Read", "tool_input": {"file_path": "source.txt"}}))
    assert result.returncode == 2, result
    print("PASS real runtime invalid Cedar fails closed")
