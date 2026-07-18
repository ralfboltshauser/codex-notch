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


SCRIPT = Path(__file__).parents[1] / "codex_notch_remote.py"
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

    def completion(self, turn_id, title):
        event = remote.completion_event(
            {
                "session_id": "019f5d4f-3a8d-76c0-8c2d-19451190e028",
                "turn_id": turn_id,
            },
            self.configuration,
        )
        event["title"] = title
        return event

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

    def test_systemd_install_owns_separate_live_service_and_restarts_it(self):
        install = self.home / ".local/lib/codex-notch"
        install.mkdir(parents=True)
        publisher = install / "codex_notch_remote-v1.py"
        observer = install / "codex_notch_live-v1.py"
        publisher.write_text("publisher")
        observer.write_text("observer")
        with mock.patch.object(remote.subprocess, "run") as run:
            remote.install_systemd_units(publisher)
        systemd = self.home / ".config/systemd/user"
        service = (systemd / "codex-notch-live.service").read_text()
        self.assertIn(str(observer), service)
        self.assertIn("Restart=always", service)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertIn(
            ["systemctl", "--user", "enable", "--now", "codex-notch-live.service"],
            commands,
        )
        self.assertIn(
            ["systemctl", "--user", "restart", "codex-notch-live.service"],
            commands,
        )

    def test_hook_enqueues_before_scheduling_background_delivery(self):
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

        queued_when_scheduled = []

        def record_scheduled_delivery():
            queued_when_scheduled.extend(remote.outbox_directory().glob("*.json"))

        with mock.patch.object(
            remote,
            "trigger_background_flush",
            side_effect=record_scheduled_delivery,
        ) as trigger, mock.patch.object(remote, "flush_outbox") as flush, mock.patch.object(
            remote,
            "send_envelope",
        ) as send:
            self.assertEqual(remote.run_hook(payload), 0)

        trigger.assert_called_once_with()
        flush.assert_not_called()
        send.assert_not_called()
        self.assertEqual(len(queued_when_scheduled), 1)
        queued = list(remote.outbox_directory().glob("*.json"))
        self.assertEqual(queued, queued_when_scheduled)
        event = json.loads(queued[0].read_text())
        self.assertIsInstance(event.pop(remote.LOCAL_QUEUE_ORDER_KEY), int)
        self.assertEqual(event["title"], "Build the overlay")
        self.assertEqual(event["source_label"], "Remote Ubuntu")
        self.assertNotIn("outcome", event)
        self.assertNotIn("private", json.dumps(event).lower())

        self.assertEqual(remote.flush_outbox(), 1)
        self.assertEqual(list(remote.outbox_directory().glob("*.json")), [])
        self.assertEqual(len(ProtocolHandler.received), 1)
        self.assertEqual(ProtocolHandler.received[0]["event"], event)

    def test_atomic_json_write_fsyncs_the_file_and_containing_directory(self):
        destination = remote.outbox_directory() / ("d" * 64 + ".json")
        with mock.patch.object(remote.os, "fsync", wraps=os.fsync) as fsync:
            remote.atomic_json_write(destination, {"event_id": "d" * 64})
        self.assertGreaterEqual(fsync.call_count, 2)
        self.assertEqual(json.loads(destination.read_text())["event_id"], "d" * 64)

    def test_hook_does_not_attempt_delivery_when_receiver_is_offline(self):
        remote.atomic_json_write(remote.config_file(), {
            **self.configuration,
            "endpoint_port": 65534,
        })
        payload = io.StringIO(json.dumps({
            "session_id": "019f5d4f-3a8d-76c0-8c2d-19451190e028",
            "turn_id": "turn-offline",
            "hook_event_name": "Stop",
        }))
        with mock.patch.object(remote, "trigger_background_flush") as trigger, mock.patch.object(
            remote,
            "flush_outbox",
            side_effect=AssertionError("Stop hook must not flush the outbox"),
        ) as flush, mock.patch.object(
            remote,
            "send_envelope",
            side_effect=AssertionError("Stop hook must not perform network delivery"),
        ) as send:
            self.assertEqual(remote.run_hook(payload), 0)
        trigger.assert_called_once_with()
        flush.assert_not_called()
        send.assert_not_called()
        self.assertEqual(len(list(remote.outbox_directory().glob("*.json"))), 1)

    def test_hook_keeps_the_event_when_background_trigger_fails(self):
        remote.atomic_json_write(remote.config_file(), self.configuration)
        payload = io.StringIO(json.dumps({
            "session_id": "019f5d4f-3a8d-76c0-8c2d-19451190e028",
            "turn_id": "turn-trigger-failure",
            "hook_event_name": "Stop",
        }))
        with mock.patch.object(
            remote.subprocess,
            "run",
            side_effect=remote.subprocess.TimeoutExpired("systemctl", 0.5),
        ) as run:
            self.assertEqual(remote.run_hook(payload), 0)
        self.assertEqual(len(list(remote.outbox_directory().glob("*.json"))), 1)
        self.assertIn("--no-block", run.call_args.args[0])
        self.assertEqual(run.call_args.kwargs["timeout"], 0.5)

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

    def test_enqueue_at_capacity_retains_newest_and_removes_oldest(self):
        directory = remote.outbox_directory()
        directory.mkdir(parents=True)
        timestamp = time.time() - remote.OUTBOX_MAX_EVENTS - 1
        existing = []
        for index in range(remote.OUTBOX_MAX_EVENTS):
            path = directory / ("%064x.json" % index)
            path.write_text("{}")
            os.utime(path, (timestamp + index, timestamp + index))
            existing.append(path)

        newest = self.completion("turn-at-capacity", "newest")
        newest_path = remote.enqueue(newest)
        queued = list(directory.glob("*.json"))

        self.assertEqual(len(queued), remote.OUTBOX_MAX_EVENTS)
        self.assertTrue(newest_path.exists())
        self.assertFalse(existing[0].exists())

    def test_enqueue_at_capacity_protects_newest_when_clock_regresses(self):
        directory = remote.outbox_directory()
        directory.mkdir(parents=True)
        future = time.time() + 60 * 60
        existing = []
        for index in range(remote.OUTBOX_MAX_EVENTS):
            path = directory / ("%064x.json" % index)
            path.write_text("{}")
            os.utime(path, (future + index, future + index))
            existing.append(path)

        newest = self.completion("turn-after-clock-regression", "logical newest")
        with mock.patch.object(remote.time, "time_ns", return_value=1):
            newest_path = remote.enqueue(newest)
        queued = list(directory.glob("*.json"))

        self.assertEqual(len(queued), remote.OUTBOX_MAX_EVENTS)
        self.assertTrue(newest_path.exists())
        self.assertFalse(existing[0].exists())

    def test_concurrent_enqueues_keep_both_new_events_and_exact_capacity(self):
        directory = remote.outbox_directory()
        directory.mkdir(parents=True)
        future = time.time() + 60 * 60
        existing = []
        for index in range(remote.OUTBOX_MAX_EVENTS):
            path = directory / ("%064x.json" % index)
            path.write_text("{}")
            os.utime(path, (future + index, future + index))
            existing.append(path)
        events = [
            self.completion("turn-concurrent-one", "concurrent one"),
            self.completion("turn-concurrent-two", "concurrent two"),
        ]
        barrier = threading.Barrier(3)
        results = []
        errors = []

        def writer(event):
            try:
                barrier.wait()
                results.append(remote.enqueue(event))
            except Exception as error:
                errors.append(error)

        threads = [threading.Thread(target=writer, args=(event,)) for event in events]
        for thread in threads:
            thread.start()
        with mock.patch.object(remote.time, "time_ns", return_value=1):
            barrier.wait()
            for thread in threads:
                thread.join(timeout=5)

        self.assertEqual(errors, [])
        self.assertTrue(all(not thread.is_alive() for thread in threads))
        self.assertEqual(len(list(directory.glob("*.json"))), remote.OUTBOX_MAX_EVENTS)
        self.assertEqual(len(results), 2)
        self.assertTrue(all(path.exists() for path in results))
        self.assertEqual(sum(not path.exists() for path in existing), 2)
        orders = [json.loads(path.read_text())[remote.LOCAL_QUEUE_ORDER_KEY] for path in results]
        self.assertEqual(len(set(orders)), 2)
        self.assertEqual(remote.outbox_lock_file().stat().st_mode & 0o777, 0o600)
        self.assertEqual(remote.state_root().stat().st_mode & 0o777, 0o700)

    def test_outbox_lock_acquisition_is_bounded(self):
        started = time.monotonic()
        with remote.outbox_lock():
            with self.assertRaises(TimeoutError):
                with remote.outbox_lock(timeout=0.02):
                    self.fail("contended lock unexpectedly acquired")
        self.assertLess(time.monotonic() - started, 0.5)

    def test_inflight_failure_survives_capacity_prune_without_blocking_enqueue(self):
        remote.atomic_json_write(remote.config_file(), self.configuration)
        first = self.completion("turn-inflight-first", "first")
        second = self.completion("turn-inflight-second", "second")
        newest = self.completion("turn-inflight-newest", "newest")
        with mock.patch.object(remote, "OUTBOX_MAX_EVENTS", 2):
            first_path = remote.enqueue(first)
            second_path = remote.enqueue(second)
            newest_paths = []

            def fail_after_concurrent_enqueue(*_args, **_kwargs):
                newest_paths.append(remote.enqueue(newest))
                raise ConnectionError("receiver offline")

            with mock.patch.object(
                remote, "send_envelope", side_effect=fail_after_concurrent_enqueue
            ):
                self.assertEqual(remote.flush_outbox(), 0)

        queued = list(remote.outbox_directory().glob("*.json"))
        self.assertEqual(len(queued), 2)
        self.assertTrue(first_path.exists())
        self.assertFalse(second_path.exists())
        self.assertEqual(len(newest_paths), 1)
        self.assertTrue(newest_paths[0].exists())

    def test_flush_replays_creation_order_and_skips_corrupt_files(self):
        remote.atomic_json_write(remote.config_file(), self.configuration)
        directory = remote.outbox_directory()
        first = self.completion("turn-first", "first")
        second = self.completion("turn-second", "second")
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

    def test_flush_quarantines_non_object_events_without_blocking_later_work(self):
        remote.atomic_json_write(remote.config_file(), self.configuration)
        directory = remote.outbox_directory()
        invalid_paths = []
        for index, value in enumerate(([], None, "not an event")):
            path = directory / ("%064x.json" % (index + 1))
            remote.atomic_json_write(path, value)
            timestamp = time.time() - 60 + index
            os.utime(path, (timestamp, timestamp))
            invalid_paths.append(path)
        valid = self.completion("turn-after-invalid", "after invalid")
        remote.enqueue(valid)

        self.assertEqual(remote.flush_outbox(), 1)
        self.assertEqual(
            [envelope["event"]["title"] for envelope in ProtocolHandler.received],
            ["after invalid"],
        )
        self.assertEqual(
            {path.name for path in (directory / "invalid").glob("*.json")},
            {path.name for path in invalid_paths},
        )

    def test_flush_uses_persisted_queue_order_when_file_timestamps_match(self):
        remote.atomic_json_write(remote.config_file(), self.configuration)
        first = self.completion("turn-first", "first")
        second = self.completion("turn-second", "second")
        with mock.patch.object(remote.time, "time_ns", side_effect=[100, 200]):
            first_path = remote.enqueue(first)
            second_path = remote.enqueue(second)
        same_timestamp = time.time() - 60
        os.utime(first_path, (same_timestamp, same_timestamp))
        os.utime(second_path, (same_timestamp, same_timestamp))

        self.assertEqual(remote.flush_outbox(), 2)
        self.assertEqual(
            [envelope["event"]["title"] for envelope in ProtocolHandler.received],
            ["first", "second"],
        )

    def test_flush_retains_event_until_a_matching_acceptance(self):
        remote.atomic_json_write(remote.config_file(), self.configuration)
        event = self.completion("turn-retained", "retain me")
        responses = [
            {"status": "rejected", "event_id": event["event_id"]},
            {"status": "accepted", "event_id": "f" * 64},
            ConnectionError("acknowledgement lost"),
            [],
            None,
            "not an acknowledgement",
        ]
        for index, response in enumerate(responses):
            with self.subTest(response=response):
                path = remote.enqueue(event)
                kwargs = ({"side_effect": response} if isinstance(response, Exception)
                          else {"return_value": response})
                with mock.patch.object(remote, "send_envelope", **kwargs):
                    self.assertEqual(remote.flush_outbox(), 0)
                self.assertTrue(path.exists())
                if index + 1 < len(responses):
                    path.unlink()

    def test_ping_uses_authenticated_protocol(self):
        acknowledgement = remote.send_envelope(self.configuration, "ping")
        self.assertEqual(acknowledgement["status"], "pong")
        self.assertEqual(ProtocolHandler.received[0]["token"], "a" * 64)

    def test_ping_retries_transient_receiver_startup_failure(self):
        with mock.patch.object(remote, "send_envelope", side_effect=[
            ConnectionRefusedError("receiver is starting"),
            {"protocol_version": 1, "status": "pong"},
        ]) as send, mock.patch.object(remote.time, "sleep") as sleep:
            acknowledgement = remote.ping_receiver(self.configuration, attempts=2)
        self.assertEqual(acknowledgement["status"], "pong")
        self.assertEqual(send.call_count, 2)
        sleep.assert_called_once_with(0.25)

    def test_ping_rejects_non_object_acknowledgements_without_a_traceback(self):
        remote.atomic_json_write(remote.config_file(), self.configuration)
        for acknowledgement in ([], None, "not an acknowledgement"):
            with self.subTest(acknowledgement=acknowledgement):
                stderr = io.StringIO()
                with mock.patch.object(
                    remote, "send_envelope", return_value=acknowledgement
                ), mock.patch("sys.stderr", stderr):
                    self.assertEqual(remote.main(["--ping"]), 1)
                self.assertIn("Could not reach Codex Notch", stderr.getvalue())
                self.assertNotIn("Traceback", stderr.getvalue())

    def test_ping_failure_is_concise_and_does_not_leak_a_traceback(self):
        remote.atomic_json_write(remote.config_file(), self.configuration)
        stderr = io.StringIO()
        with mock.patch.object(
            remote,
            "send_envelope",
            side_effect=ConnectionRefusedError("connection refused"),
        ), mock.patch("sys.stderr", stderr):
            self.assertEqual(remote.main(["--ping"]), 1)
        message = stderr.getvalue()
        self.assertIn("Could not reach Codex Notch on this Mac", message)
        self.assertIn("127.0.0.1", message)
        self.assertNotIn("Traceback", message)

    def test_health_requires_an_installed_trusted_hook_and_reaches_receiver(self):
        remote.install(self.configuration, script_path=SCRIPT)
        stderr = io.StringIO()
        with mock.patch("sys.stderr", stderr):
            self.assertEqual(remote.main(["--health"]), 1)
        self.assertIn("still needs trust", stderr.getvalue())
        self.assertEqual(ProtocolHandler.received, [])

        root = remote.read_hooks(remote.hooks_file())
        key = next(iter(remote.hook_state_keys(root, remote.hooks_file())))
        remote.codex_config_file().write_text(
            '[hooks.state.%s]\ntrusted_hash = "sha256:test"\n' % json.dumps(key)
        )

        self.assertEqual(remote.main(["--health"]), 0)
        self.assertEqual(ProtocolHandler.received[0]["kind"], "ping")

    def test_health_reports_a_missing_completion_hook(self):
        remote.atomic_json_write(remote.config_file(), self.configuration)
        remote.hooks_file().parent.mkdir(parents=True, exist_ok=True)
        remote.hooks_file().write_text('{"hooks":{}}')
        stderr = io.StringIO()
        with mock.patch("sys.stderr", stderr):
            self.assertEqual(remote.main(["--health"]), 1)
        self.assertIn("hook is not installed", stderr.getvalue())

    def test_uninstall_removes_configuration_and_queued_metadata(self):
        remote.atomic_json_write(remote.config_file(), self.configuration)
        (remote.config_root() / "stale").write_text("stale metadata")
        remote.atomic_json_write(remote.outbox_directory() / ("a" * 64 + ".json"), {})
        hooks = {"hooks": {
            "Stop": [{"hooks": [
                {"type": "command", "command": "/other"},
                {"type": "command", "command": str(SCRIPT) + " " + remote.MARKER},
            ]}],
        }}
        remote.atomic_json_write(remote.hooks_file(), hooks)
        remote.atomic_json_write(
            remote.hooks_file().with_name(remote.hooks_file().name + ".bak"),
            hooks,
        )
        owned_state_key = "%s:stop:0:1" % remote.hooks_file()
        remote.codex_config_file().write_text(
            "[hooks.state]\n\n"
            "[hooks.state.%s]\ntrusted_hash = \"sha256:owned\"\n\n"
            "[hooks.state.\"plugin:unrelated\"]\ntrusted_hash = \"sha256:unrelated\"\n"
            % json.dumps(owned_state_key)
        )
        installed_script = self.home / ".local/lib/codex-notch/codex_notch_remote-v1.py"
        installed_script.parent.mkdir(parents=True)
        installed_script.write_text("stale publisher")
        installed_live = installed_script.with_name("codex_notch_live-v1.py")
        installed_live.write_text("stale observer")
        systemd = self.home / ".config/systemd/user"
        systemd.mkdir(parents=True)
        (systemd / "codex-notch-live.service").write_text("stale service")

        with mock.patch.object(remote.subprocess, "run"):
            remote.uninstall()
        self.assertFalse(remote.config_file().exists())
        self.assertFalse(remote.config_root().exists())
        self.assertFalse(remote.state_root().exists())
        self.assertFalse(installed_script.exists())
        self.assertFalse(installed_live.exists())
        self.assertFalse((systemd / "codex-notch-live.service").exists())
        root = json.loads(remote.hooks_file().read_text())
        self.assertEqual(root["hooks"]["Stop"][0]["hooks"][0]["command"], "/other")
        backup = json.loads(
            remote.hooks_file().with_name(remote.hooks_file().name + ".bak").read_text()
        )
        self.assertEqual(backup["hooks"]["Stop"][0]["hooks"][0]["command"], "/other")
        config = remote.codex_config_file().read_text()
        self.assertNotIn(owned_state_key, config)
        self.assertIn("plugin:unrelated", config)


if __name__ == "__main__":
    unittest.main()
