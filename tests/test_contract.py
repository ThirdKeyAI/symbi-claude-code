"""Regression tests at the shipping hook entrypoints; no third-party packages."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

PLUGIN = Path(__file__).resolve().parents[1]


class HookContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root), SYMBIONT_PROJECT_DIR=str(self.root))
        self.env.pop("SYMBIONT_MANAGED", None)

    def hook(self, event, cursor=False, env=None):
        raw = event if isinstance(event, str) else json.dumps(event)
        return subprocess.run(["bash", str(PLUGIN / "scripts" / ("cursor-guard.sh" if cursor else "policy-guard.sh"))],
                              input=raw, text=True, capture_output=True, env=env or self.env)

    def call(self, name="Read", **args):
        return {"tool_name": name, "tool_input": args}

    def denied(self, event, cursor=False, env=None):
        reply = self.hook(event, cursor, env)
        if cursor:
            self.assertEqual(reply.returncode, 0, reply.stderr)
            self.assertEqual(json.loads(reply.stdout)["permission"], "deny", reply.stdout)
        else:
            self.assertEqual(reply.returncode, 2, reply.stdout + reply.stderr)
            self.assertEqual(reply.stdout, "")
        return reply

    def policy(self, text):
        (self.root / ".symbiont").mkdir(exist_ok=True)
        (self.root / ".symbiont/local-policy.toml").write_text(text)

    def evaluator(self, behavior="allow"):
        (self.root / "policies").mkdir(exist_ok=True)
        (self.root / "policies/main.cedar").write_text("permit(principal, action, resource);")
        binary = self.root / "bin"
        binary.mkdir(exist_ok=True)
        fake = binary / "symbi"
        fake.write_text(f"#!{sys.executable}\n" + '''import json, os, sys, time
event = json.load(sys.stdin)
mode = os.environ['TEST_EVALUATOR']
if mode == 'timeout': time.sleep(10)
if mode == 'exit': sys.exit(1)
if mode == 'empty': sys.exit(0)
if mode == 'garbage': print('allow'); sys.exit(0)
with open(os.environ['TEST_CAPTURE'], 'w') as capture: json.dump(event, capture)
reply = {'decision': 'allow', 'tool': event['tool_name'],
         'policies_dir': sys.argv[-1], 'reason': 'allow policies matched: main_0'}
if mode == 'disabled': reply['reason'] = 'cedar feature disabled at build time; allowing'
if mode == 'no-policies': reply['reason'] = 'no .cedar policies loaded; allowing by default'
if mode == 'deny': reply['decision'] = 'deny'
if mode == 'wrong-tool': reply['tool'] = 'unknown'
if mode == 'wrong-dir': reply['policies_dir'] = '/elsewhere'
if mode == 'unknown': reply['decision'] = 'maybe'
print(json.dumps(reply))
''')
        fake.chmod(0o755)
        self.env.update(PATH=str(binary) + os.pathsep + os.environ["PATH"], TEST_EVALUATOR=behavior, TEST_CAPTURE=str(self.root / "capture.json"))

    def test_malformed_and_ambiguous_json(self):
        invalid = ['{broken', 'null', '[]', '{}', '{"tool_name":"Read","tool_input":{"file_path":"ok","file_path":".env"}}',
                   '{"tool_name":"Read","tool_input":{"file_path":NaN}}']
        for event in invalid:
            for cursor in (False, True):
                with self.subTest(event=event, cursor=cursor):
                    self.denied(event, cursor)

    def test_typed_required_fields(self):
        for value in (None, [], {}, True, 2, "", "\0bad", "bad\npath", "\ud800"):
            with self.subTest(value=repr(value)):
                self.denied(self.call(file_path=value))
        self.denied(self.call("Bash", command=None))
        self.denied({"tool_name": "Read", "tool_input": []})

    def test_unicode_and_escaped_inputs(self):
        self.denied(r'{"tool_name":"Read","tool_input":{"file_path":"\u002eenv"}}')
        self.assertEqual(self.hook(self.call("Bash", command='printf "hello\\world"\nprintf ok')).returncode, 0)
        self.assertEqual(self.hook(self.call(file_path='src/hello "world".rs')).returncode, 0)

    def test_environment_is_not_managed_authority(self):
        for value in ("true", "false", "0"):
            self.denied(self.call(file_path=".env"), env=dict(self.env, SYMBIONT_MANAGED=value))

    def test_all_named_path_fields_are_checked(self):
        self.denied(self.call(file_path="safe", path=".env"))
        self.denied(self.call("Grep", path=".env", pattern="."))
        self.denied(self.call("Glob", path=".ssh", pattern="*"))
        self.denied(self.call("NotebookEdit", notebook_path=".env"))

    def test_normalized_and_symlink_paths(self):
        (self.root / "source").mkdir()
        (self.root / "public").symlink_to(self.root / ".env")
        for path in ("source/../.env", "./.ssh//", "public"):
            self.denied(self.call(file_path=path))
        self.assertEqual(self.hook(self.call(file_path="source/../README.md")).returncode, 0)

    def test_control_paths_before_permissive_or_allowlist(self):
        self.policy('[mode]\nmode="permissive"\n[allow]\npaths=["*"]\n')
        (self.root / "alias").symlink_to(self.root / ".symbiont", target_is_directory=True)
        for path in (".symbiont/disabled", "alias/local-policy.toml", "sub/../.cursor/hooks.json", ".claude/settings.local.json",
                     "policies/main.cedar", "symbiont.toml", ".mcp.json", str(PLUGIN / "scripts/core/policy.py")):
            with self.subTest(path=path):
                self.denied(self.call("Write", file_path=path))
        self.assertEqual(self.hook(self.call("Write", file_path="src/main.rs")).returncode, 0)

    def test_cursor_edit_aliases_and_extra_fields(self):
        for name in ("StrReplace", "str_replace", "Delete", "Write"):
            for path in (".symbiont/local-policy.toml", "policies/main.cedar", ".github/workflows/test.yml"):
                self.denied(self.call(name, path=path, old_string="old", new_string="new", command="printf harmless"), True)
            reply = self.hook(self.call(name, path="src/main.rs", old_string="old", new_string="new"), True)
            self.assertEqual(json.loads(reply.stdout)["permission"], "allow")

    def test_external_targets_of_control_symlinks(self):
        (self.root / ".symbiont").mkdir()
        external = self.root / "operator-policy.toml"
        external.write_text('[mode]\nmode="balanced"')
        (self.root / ".symbiont/local-policy.toml").symlink_to(external)
        for spelling in (".symbiont/local-policy.toml", str(external)):
            self.denied(self.call("Write", file_path=spelling))
        self.evaluator()
        external_cedar = self.root / "operator-policy.cedar"
        external_cedar.write_text("permit(principal, action, resource);")
        (self.root / "policies/link.cedar").symlink_to(external_cedar)
        self.denied(self.call("Edit", file_path=str(external_cedar)))

    def test_real_toml_multiline_literals_escapes(self):
        self.policy('''[deny]
paths = [
  'private/data,one', # literal comma is part of the pattern
  "private/quoted\\\"name",
]
''')
        self.denied(self.call(file_path="private/data,one"))
        self.denied(self.call(file_path='private/quoted"name'))
        self.assertEqual(self.hook(self.call(file_path="private/public")).returncode, 0)

    def test_invalid_policy_fails_closed(self):
        for text in ('[deny]\npaths=[', '[deny]\npaths="secret"', '[mode]\nmode="unknown"', '[deny]\npath=["secret"]', '[require_approval]\npaths=["private"]'):
            self.policy(text)
            self.denied(self.call(file_path="source.rs"))

    def test_local_deny_wins_over_allow(self):
        self.policy('[deny]\npaths=["private"]\ncommands=["destroy"]\n[allow]\npaths=["*"]\ncommands=["destroy"]')
        self.denied(self.call(file_path="private/data"))
        self.denied(self.call("Bash", command="destroy"))

    def test_command_exception_is_exact(self):
        self.policy('[allow]\ncommands=["echo hello"]')
        self.assertEqual(self.hook(self.call("Bash", command="echo hello")).returncode, 0)
        self.denied(self.call("Bash", command="echo hello; rm -rf /"))

    def test_runtime_full_payload_preserved(self):
        self.evaluator()
        for name in ("Read", "Grep", "Glob", "mcp__example__lookup", "FutureTool"):
            event = self.call(name, file_path="README.md", pattern="quote\\\"", options={"limit": 10, "enabled": True})
            event["tool_use_id"] = "test-call"
            result = self.hook(event)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads((self.root / "capture.json").read_text()), event)

    def test_runtime_failures_deny_both_adapters(self):
        self.evaluator()
        for mode in ("exit", "empty", "garbage", "disabled", "no-policies", "deny", "wrong-tool", "wrong-dir", "unknown"):
            self.env["TEST_EVALUATOR"] = mode
            for cursor in (False, True):
                with self.subTest(mode=mode, cursor=cursor):
                    self.denied(self.call("Shell" if cursor else "Bash", command="printf harmless"), cursor)

    def test_runtime_timeout(self):
        self.evaluator("timeout")
        self.denied(self.call(file_path="README.md"))

    def test_padded_commands_reach_runtime_without_stalling(self):
        self.evaluator("deny")
        for command in ("git push " + " " * 6000 + "origin main", "curl word " * 5000):
            started = time.monotonic()
            self.denied(self.call("Bash", command=command))
            self.assertLess(time.monotonic() - started, 2)
            self.assertEqual(json.loads((self.root / "capture.json").read_text())["tool_input"]["command"], command)
        self.denied(self.call("Bash", command="a" * (65536 + 1)))

    def test_empty_configured_policies_deny(self):
        (self.root / "policies").mkdir()
        self.denied(self.call(file_path="README.md"))

    def test_cursor_workspace_root_survives_subdirectory_cwd(self):
        self.policy('[deny]\ncommands=["forbidden"]')
        sub = self.root / "sub"
        sub.mkdir()
        event = dict(self.call("Shell", command="forbidden"), cwd=str(sub), workspace_roots=[str(self.root)])
        env = dict(self.env)
        env.pop("SYMBIONT_PROJECT_DIR")
        self.denied(event, True, env)

    def test_cursor_warning_contract_depends_on_event(self):
        event = self.call("Shell", command="sudo apt update")
        self.denied(event, True)
        event["hook_event_name"] = "beforeShellExecution"
        self.assertEqual(json.loads(self.hook(event, True).stdout)["permission"], "ask")

    def test_failure_to_start_engine_denies(self):
        binary = self.root / "bin"
        binary.mkdir()
        (binary / "python3").write_text("#!/bin/sh\nexit 1\n")
        (binary / "python3").chmod(0o755)
        env = dict(self.env, PATH=str(binary) + os.pathsep + os.environ["PATH"])
        for cursor in (False, True):
            self.denied(self.call(file_path="README.md"), cursor, env)

    def test_decisions_logged_without_raw_input(self):
        self.denied(self.call(file_path=".env"))
        result = self.hook(self.call("Bash", command="printf PRIVATE_MARKER"))
        self.assertEqual(result.returncode, 0)
        text = (self.root / ".symbiont/audit/tool-usage.jsonl").read_text()
        self.assertNotIn("PRIVATE_MARKER", text)
        self.assertEqual([json.loads(line)["decision"] for line in text.splitlines()], ["deny", "allow"])

    def test_audit_does_not_follow_symlink(self):
        (self.root / ".symbiont").mkdir()
        other = self.root / "other"
        other.mkdir()
        (self.root / ".symbiont/audit").symlink_to(other, target_is_directory=True)
        self.assertEqual(self.hook(self.call(file_path="README.md")).returncode, 0)
        self.assertFalse((other / "tool-usage.jsonl").exists())

    def test_nonregular_config_and_audit_do_not_stall(self):
        self.policy("")
        path = self.root / ".symbiont/local-policy.toml"
        path.unlink()
        os.mkfifo(path)
        started = time.monotonic()
        self.denied(self.call(file_path="README.md"))
        self.assertLess(time.monotonic() - started, 2)
        path.unlink()
        log = self.root / ".symbiont/audit/tool-usage.jsonl"
        log.unlink()
        os.mkfifo(log)
        started = time.monotonic()
        self.assertEqual(self.hook(self.call(file_path="README.md")).returncode, 0)
        self.assertLess(time.monotonic() - started, 2)

    def test_registration_blocks_harness_failures_and_covers_every_tool(self):
        data = json.loads((PLUGIN / "hooks/hooks.json").read_text())
        for entry in data["hooks"]["PreToolUse"]:
            self.assertNotIn("matcher", entry)
            for hook in entry["hooks"]:
                self.assertEqual(hook["onFailure"], "block")
                self.assertEqual(hook["command"], "bash")
                self.assertEqual(len(hook["args"]), 1)

    def test_install_merges_and_is_idempotent(self):
        project = self.root / 'project with "quotes" and $dollar'
        (project / ".cursor").mkdir(parents=True)
        config = project / ".cursor/hooks.json"
        config.write_text('{"version":1,"hooks":{"stop":[{"command":"echo ok"}]}}')
        installer = ["bash", str(PLUGIN / "adapters/cursor/install.sh"), str(project)]
        subprocess.run(installer, check=True, capture_output=True)
        installed = config.read_bytes()
        subprocess.run(installer, check=True, capture_output=True)
        self.assertEqual(config.read_bytes(), installed)
        data = json.loads(installed)
        self.assertEqual(data["hooks"]["stop"], [{"command": "echo ok"}])
        command = data["hooks"]["preToolUse"][0]["command"]
        result = subprocess.run(command, shell=True, input=json.dumps(self.call(file_path=".env")), text=True, capture_output=True)
        self.assertEqual(json.loads(result.stdout)["permission"], "deny")
        self.assertTrue(data["hooks"]["preToolUse"][0]["failClosed"])


if __name__ == "__main__":
    unittest.main()
