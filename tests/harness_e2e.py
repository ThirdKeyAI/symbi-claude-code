#!/usr/bin/env python3
"""Installed-client hook smoke test using only a local synthetic provider.

Usage: python3 -I tests/harness_e2e.py /path/to/claude /path/to/symbi
The test uses temporary HOME/config/project/plugin copies, no account credentials,
and harmless Read calls. It does not invoke an external model service.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import threading

SOURCE = Path(__file__).resolve().parents[1]
CLIENT = Path(sys.argv[1]).resolve(strict=True)
RUNTIME = Path(sys.argv[2]).resolve(strict=True)


def run_case(root, mode):
    project = root / mode
    project.mkdir()
    (project / "public.txt").write_text("PUBLIC_FIXTURE_CONTENT")
    (project / "blocked.txt").write_text("BLOCKED_FIXTURE_CONTENT")
    (project / "policies").mkdir()
    (project / "policies/main.cedar").write_text('''permit(principal, action, resource);
forbid(principal, action, resource) when {
  action == Symbi::Action::"tool_call::Read" && context.tool_input.file_path like "*blocked.txt"
};
''')
    plugin = root / (mode + "-plugin")
    # Copy only functional plugin assets; never load local development files.
    for directory in (".claude-plugin", "hooks", "scripts"):
        shutil.copytree(SOURCE / directory, plugin / directory, ignore=shutil.ignore_patterns("__pycache__"))
    config_path = plugin / "hooks/hooks.json"
    config = json.loads(config_path.read_text())
    guard = config["hooks"]["PreToolUse"][0]["hooks"][0]
    if mode == "missing-hook":
        guard["args"] = [str(plugin / "missing.sh")]
    elif mode == "hook-timeout":
        guard.update(command="sleep", args=["10"], timeout=0.1)
    config_path.write_text(json.dumps(config))
    received = []
    errors = []

    class Provider(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            try:
                value = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                assert self.path.split("?")[0] in ("/v1/messages", "/v1/messages/count_tokens")
                if self.path.split("?")[0].endswith("count_tokens"):
                    body = b'{"input_tokens":1}'
                    kind = "application/json"
                else:
                    assert value["model"] == "fixture"
                    results = [block for message in value["messages"] if isinstance(message.get("content"), list)
                               for block in message["content"] if block["type"] == "tool_result"]
                    if results:
                        received.extend(results)
                        content = [{"type": "text", "text": "fixture complete"}]
                        stop = "end_turn"
                    else:
                        filenames = ("public.txt", "blocked.txt") if mode == "policy" else ("public.txt",)
                        content = [{"type": "tool_use", "id": "fixture-" + name, "name": "Read", "input": {"file_path": str(project / name)}} for name in filenames]
                        stop = "tool_use"
                    message = dict(id="fixture", type="message", role="assistant", model="fixture", content=content,
                                   stop_reason=stop, stop_sequence=None, usage=dict(input_tokens=1, output_tokens=1))
                    if value.get("stream"):
                        events = [dict(type="message_start", message={**message, "content": [], "stop_reason": None, "usage": dict(input_tokens=1, output_tokens=0)})]
                        for index, block in enumerate(content):
                            initial = {**block, "text": ""} if block["type"] == "text" else {**block, "input": {}}
                            delta = dict(type="text_delta", text=block["text"]) if block["type"] == "text" else dict(type="input_json_delta", partial_json=json.dumps(block["input"]))
                            events.extend([dict(type="content_block_start", index=index, content_block=initial),
                                           dict(type="content_block_delta", index=index, delta=delta), dict(type="content_block_stop", index=index)])
                        events.extend([dict(type="message_delta", delta=dict(stop_reason=stop, stop_sequence=None), usage=dict(output_tokens=1)), dict(type="message_stop")])
                        body = "".join("event: " + event["type"] + "\ndata: " + json.dumps(event) + "\n\n" for event in events).encode()
                        kind = "text/event-stream"
                    else:
                        body = json.dumps(message).encode()
                        kind = "application/json"
                self.send_response(200)
                self.send_header("Content-Type", kind)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except Exception as error:
                errors.append(str(error))
                self.send_error(500)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Provider)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    home = root / (mode + "-home")
    home.mkdir()
    env = {"HOME": str(home), "PATH": str(root / "bin") + os.pathsep + os.defpath,
           "LANG": "C.UTF-8", "ANTHROPIC_BASE_URL": f"http://127.0.0.1:{server.server_port}",
           "ANTHROPIC_API_KEY": "synthetic-test-key", "CLAUDE_CONFIG_DIR": str(home / "config"),
           "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1", "DISABLE_AUTOUPDATER": "1"}
    try:
        result = subprocess.run([str(CLIENT), "-p", "Run the requested harmless fixture reads.", "--model", "fixture",
                                 "--output-format", "json", "--permission-mode", "dontAsk", "--allowedTools", "Read",
                                 "--tools", "Read", "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
                                 "--setting-sources", "", "--no-session-persistence", "--plugin-dir", str(plugin)],
                                cwd=project, env=env, text=True, capture_output=True, timeout=30)
        assert not errors, errors
        assert result.returncode == 0, (result.returncode, result.stderr[-2000:], result.stdout[-2000:])
        assert received, ("No tool results reached the synthetic provider", result.stdout[-2000:])
        by_id = {row["tool_use_id"]: row for row in received}
        public = by_id["fixture-public.txt"]
        if mode == "policy":
            assert "PUBLIC_FIXTURE_CONTENT" in json.dumps(public) and not public.get("is_error"), public
            denied = by_id["fixture-blocked.txt"]
            assert denied.get("is_error") and "BLOCKED_FIXTURE_CONTENT" not in json.dumps(denied), denied
            assert "Cedar" in json.dumps(denied), denied
        else:
            assert public.get("is_error") and "PUBLIC_FIXTURE_CONTENT" not in json.dumps(public), public
            assert "onFailure" in json.dumps(public), public
        print(f"PASS installed client {mode}")
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


version = subprocess.check_output([str(CLIENT), "--version"], text=True).strip()
match = re.match(r"(\d+)\.(\d+)\.(\d+)", version)
assert match and tuple(map(int, match.groups())) >= (2, 1, 295), "Client 2.1.295+ required"
print(version)
with tempfile.TemporaryDirectory(prefix="plugin-harness-") as temporary:
    root = Path(temporary)
    (root / "bin").mkdir()
    (root / "bin/symbi").symlink_to(RUNTIME)
    (root / "bin/python3").symlink_to(Path(sys.executable).resolve())
    for mode in ("policy", "missing-hook", "hook-timeout"):
        run_case(root, mode)
