import importlib.util
import io
import json
import os
from pathlib import Path
import socketserver
import struct
import tempfile
import threading
import time
import unittest
from unittest import mock


SCRIPT = Path(__file__).parents[2] / "remote" / "codex_notch_remote.py"
SPEC = importlib.util.spec_from_file_location("codex_notch_remote", SCRIPT)
remote = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(remote)


class ProtocolHandler(socketserver.BaseRequestHandler):
    received = []

    def handle(self):
        size = struct.unpack("!I", self.request.recv(4))[0]
        payload = b""
        while len(payload) < size:
            payload += self.request.recv(size - len(payload))
        envelope = json.loads(payload)
        self.received.append(envelope)
        if envelope["kind"] == "ping":
            acknowledgement = {"protocol_version": 1, "status": "pong"}
        else:
            acknowledgement = {
                "protocol_version": 1,
                "status": "accepted",
                "event_id": envelope["event"]["event_id"],
            }
        data = json.dumps(acknowledgement).encode()
        self.request.sendall(struct.pack("!I", len(data)) + data)


class LinuxHookTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.home = Path(self.temporary.name)
        self.environment = mock.patch.dict(os.environ, {
            "HOME": str(self.home),
            "CODEX_HOME": str(self.home / ".codex"),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_STATE_HOME": str(self.home / ".state"),
        }, clear=False)
        self.environment.start()
        ProtocolHandler.received = []
        self.server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), ProtocolHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.configuration = {
            "endpoint_host": "127.0.0.1",
            "endpoint_port": self.server.server_address[1],
            "token": "a" * 64,
            "host_id": "remote-1",
            "source_name": "Remote Ubuntu",
        }

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.environment.stop()
        self.temporary.cleanup()

    def test_event_id_is_stable_and_safe_for_a_filename(self):
        value = remote.event_id("019f5d4f-3a8d-76c0-8c2d-19451190e028", "turn/../secret")
        self.assertRegex(value, r"^[0-9a-f]{64}$")
        self.assertNotIn("/", value)

    def test_install_is_idempotent_and_preserves_other_hooks(self):
        path = remote.hooks_file()
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"hooks": {
            "PostToolUse": [{"hooks": [{"type": "command", "command": "/other"}]}],
            "Stop": [{"hooks": [{"type": "command", "command": "/existing-stop"}]}],
        }}))

        with mock.patch.object(remote, "install_systemd_units"):
            remote.install(self.configuration, SCRIPT)
            remote.install(self.configuration, SCRIPT)
        root = json.loads(path.read_text())
        self.assertIn("PostToolUse", root["hooks"])
        commands = [
            handler["command"]
            for group in root["hooks"]["Stop"]
            for handler in group["hooks"]
        ]
        self.assertEqual(commands.count("/existing-stop"), 1)
        self.assertEqual(sum(remote.MARKER in command for command in commands), 1)

    def test_hook_writes_before_delivery_and_removes_after_ack(self):
        session_id = "019f5d4f-3a8d-76c0-8c2d-19451190e028"
        remote.atomic_json_write(remote.config_file(), self.configuration)
        remote.codex_home().mkdir(parents=True)
        (remote.codex_home() / "session_index.jsonl").write_text(json.dumps({
            "id": session_id,
            "thread_name": "Build the overlay",
        }) + "\n")
        payload = io.StringIO(json.dumps({
            "session_id": session_id,
            "turn_id": "turn-secret",
            "cwd": "/private/source/path",
            "hook_event_name": "Stop",
            "transcript_path": "/private/transcript.jsonl",
        }))

        self.assertEqual(remote.run_hook(payload), 0)
        self.assertEqual(list(remote.outbox_directory().glob("*.json")), [])
        self.assertEqual(len(ProtocolHandler.received), 1)
        event = ProtocolHandler.received[0]["event"]
        self.assertEqual(event["title"], "Build the overlay")
        self.assertEqual(event["source_label"], "Remote Ubuntu")
        self.assertNotIn("private", json.dumps(event).lower())

    def test_failed_delivery_remains_in_outbox(self):
        remote.atomic_json_write(remote.config_file(), {
            **self.configuration,
            "endpoint_port": 65534,
        })
        payload = io.StringIO(json.dumps({
            "session_id": "019f5d4f-3a8d-76c0-8c2d-19451190e028",
            "turn_id": "turn-offline",
            "hook_event_name": "Stop",
        }))
        with mock.patch.object(remote, "trigger_background_flush"):
            self.assertEqual(remote.run_hook(payload), 0)
            remote.trigger_background_flush.assert_called_once()
        self.assertEqual(len(list(remote.outbox_directory().glob("*.json"))), 1)

    def test_outbox_prunes_expired_and_oldest_events(self):
        directory = remote.outbox_directory()
        directory.mkdir(parents=True)
        paths = []
        for index in range(4):
            path = directory / ("%064x.json" % index)
            path.write_text("{}")
            timestamp = time.time() - (4 - index) * 60
            os.utime(path, (timestamp, timestamp))
            paths.append(path)
        expired = directory / ("f" * 64 + ".json")
        expired.write_text("{}")
        old = time.time() - 8 * 24 * 60 * 60
        os.utime(expired, (old, old))

        with mock.patch.object(remote, "OUTBOX_MAX_EVENTS", 2):
            remote.prune_outbox()
        self.assertEqual(
            [path.name for path in sorted(directory.glob("*.json"))],
            sorted([paths[2].name, paths[3].name]),
        )

    def test_flush_replays_creation_order_and_skips_corrupt_files(self):
        remote.atomic_json_write(remote.config_file(), self.configuration)
        directory = remote.outbox_directory()
        first = {"event_id": "f" * 64, "title": "first"}
        second = {"event_id": "0" * 64, "title": "second"}
        first_path = directory / (first["event_id"] + ".json")
        second_path = directory / (second["event_id"] + ".json")
        remote.atomic_json_write(first_path, first)
        time.sleep(0.01)
        (directory / ("a" * 64 + ".json")).write_text("not json")
        time.sleep(0.01)
        remote.atomic_json_write(second_path, second)

        self.assertEqual(remote.flush_outbox(), 2)
        self.assertEqual(
            [envelope["event"]["title"] for envelope in ProtocolHandler.received],
            ["first", "second"],
        )
        self.assertEqual(len(list((directory / "invalid").glob("*.json"))), 1)

    def test_ping_uses_authenticated_protocol(self):
        acknowledgement = remote.send_envelope(self.configuration, "ping")
        self.assertEqual(acknowledgement["status"], "pong")
        self.assertEqual(ProtocolHandler.received[0]["token"], "a" * 64)

    def test_uninstall_removes_configuration_and_queued_metadata(self):
        remote.atomic_json_write(remote.config_file(), self.configuration)
        remote.atomic_json_write(remote.outbox_directory() / ("a" * 64 + ".json"), {})
        remote.atomic_json_write(remote.hooks_file(), {"hooks": {
            "Stop": [{"hooks": [
                {"type": "command", "command": "/other"},
                {"type": "command", "command": str(SCRIPT) + " " + remote.MARKER},
            ]}],
        }})

        with mock.patch.object(remote.subprocess, "run"):
            remote.uninstall()
        self.assertFalse(remote.config_file().exists())
        self.assertFalse(remote.state_root().exists())
        root = json.loads(remote.hooks_file().read_text())
        self.assertEqual(root["hooks"]["Stop"][0]["hooks"][0]["command"], "/other")


if __name__ == "__main__":
    unittest.main()
