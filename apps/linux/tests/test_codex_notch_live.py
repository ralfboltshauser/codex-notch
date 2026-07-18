import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).parents[1] / "codex_notch_live.py"
SPEC = importlib.util.spec_from_file_location("codex_notch_live", SCRIPT)
live = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(live)


class ScriptedRPC:
    def __init__(
        self,
        list_rows=None,
        loaded_ids=None,
        threads=None,
        page_size=100,
        loaded_error=None,
        list_response=None,
    ):
        self.list_rows = list_rows or []
        self.loaded_ids = loaded_ids or []
        self.threads = threads or {}
        self.page_size = page_size
        self.loaded_error = loaded_error
        self.list_response = list_response
        self.calls = []

    def __call__(self, method, params, deadline):
        self.calls.append({
            "method": method,
            "params": dict(params),
            "deadline": deadline,
        })
        request_id = len(self.calls)
        if method == "thread/list":
            if self.list_response is not None:
                return self.list_response
            return {"id": request_id, "result": {"data": self.list_rows}}
        if method == "thread/loaded/list":
            if self.loaded_error is not None:
                return {"id": request_id, "error": self.loaded_error}
            cursor = params.get("cursor")
            start = int(cursor) if cursor is not None else 0
            end = min(start + self.page_size, len(self.loaded_ids))
            next_cursor = str(end) if end < len(self.loaded_ids) else None
            return {
                "id": request_id,
                "result": {
                    "data": self.loaded_ids[start:end],
                    "nextCursor": next_cursor,
                },
            }
        if method == "thread/read":
            thread_id = params.get("threadId")
            value = self.threads.get(thread_id)
            if isinstance(value, Exception):
                raise value
            if isinstance(value, dict) and ("result" in value or "error" in value):
                return value
            return {"id": request_id, "result": {"thread": value}}
        raise AssertionError("unexpected method: %s" % method)

    def call_many(self, requests, deadline):
        return [self(method, params, deadline) for method, params in requests]

    def calls_for(self, method):
        return [call for call in self.calls if call["method"] == method]


class LinuxLiveObserverTests(unittest.TestCase):
    def setUp(self):
        live.sequence = 0
        live.generation = "11111111-1111-4111-8111-111111111111"

    def synthetic_id(self, number):
        return "019f77e0-2222-7111-8111-%012x" % number

    def thread(
        self,
        thread_id,
        name,
        status=None,
        parent_id=None,
        updated_at=1_784_352_100,
    ):
        row = {
            "id": thread_id,
            "name": name,
            "status": status or {"type": "active", "activeFlags": []},
            "updatedAt": updated_at,
            "cwd": "/home/ralf/private/codex-notch",
            "gitInfo": {
                "branch": "codex/loaded-reconciliation",
                "originUrl": "git@github.com:private/secret.git",
            },
            "preview": "secret prompt content",
            "turns": [{"items": ["secret transcript"]}],
            "path": "/home/ralf/private/.codex/sessions/secret.jsonl",
            "remoteUrl": "https://example.invalid/private",
        }
        if parent_id is not None:
            row["parentThreadId"] = parent_id
        return row

    def test_snapshot_contains_only_minimum_display_metadata(self):
        snapshot = live.snapshot_from_rows([{
            "id": "019f5d4f-3a8d-76c0-8c2d-19451190e028",
            "name": "  Build   the overlay  ",
            "status": {"type": "active", "activeFlags": ["waitingOnApproval"]},
            "updatedAt": 1_784_035_200,
            "cwd": "/private/source",
            "preview": "secret prompt",
            "path": "/private/transcript.jsonl",
            "parentThreadId": None,
        }])
        self.assertEqual(snapshot["sequence"], 1)
        self.assertEqual(snapshot["tasks"][0]["title"], "Build the overlay")
        self.assertEqual(snapshot["tasks"][0]["state"], "waiting_for_approval")
        encoded = str(snapshot).lower()
        self.assertNotIn("private", encoded)
        self.assertNotIn("secret", encoded)

    def test_snapshot_includes_active_subagents_but_not_idle_root_rows(self):
        active_child = {
            "id": "019f5d4f-3a8d-76c0-8c2d-19451190e028",
            "name": "Child",
            "status": {"type": "active", "activeFlags": []},
            "parentThreadId": "019f5d4f-3a8d-76c0-8c2d-19451190e029",
        }
        idle_root = {
            "id": "019f5d4f-3a8d-76c0-8c2d-19451190e029",
            "name": "Idle",
            "status": {"type": "idle"},
            "parentThreadId": None,
        }
        tasks = live.snapshot_from_rows([active_child, idle_root])["tasks"]
        self.assertEqual(len(tasks), 1)
        self.assertEqual(tasks[0]["title"], "Child")
        self.assertEqual(tasks[0]["parent_thread_id"], idle_root["id"])
        self.assertEqual(tasks[0]["root_thread_id"], idle_root["id"])
        self.assertEqual(tasks[0]["root_title"], "Idle")

    def test_loaded_reconciliation_enumerates_before_selecting_recent_candidates(self):
        loaded_ids = [self.synthetic_id(index) for index in range(1, 76)]
        threads = {
            thread_id: self.thread(
                thread_id,
                "Loaded %d" % index,
                updated_at=1_784_400_000 + index,
            )
            for index, thread_id in enumerate(loaded_ids, start=1)
        }
        # The oldest ascending UUID is still the most recently updated baseline
        # row, so it must win a read slot before the newest UUID tail.
        threads[loaded_ids[0]]["updatedAt"] = 1_784_500_000
        rpc = ScriptedRPC(
            list_rows=[threads[loaded_ids[0]]],
            loaded_ids=loaded_ids,
            threads=threads,
            page_size=10,
        )
        reconciler = live.LoadedThreadReconciler()

        rows = reconciler.reconcile(rpc)

        self.assertIsNotNone(rows)
        read_calls = rpc.calls_for("thread/read")
        read_ids = [call["params"]["threadId"] for call in read_calls]
        expected = [loaded_ids[0]] + list(reversed(loaded_ids[-49:]))
        self.assertEqual(read_ids, expected)
        self.assertEqual(len(rpc.calls_for("thread/loaded/list")), 8)
        self.assertLess(
            max(index for index, call in enumerate(rpc.calls)
                if call["method"] == "thread/loaded/list"),
            min(index for index, call in enumerate(rpc.calls)
                if call["method"] == "thread/read"),
        )
        self.assertTrue(all(
            call["params"] == {
                "threadId": call["params"]["threadId"],
                "includeTurns": False,
            }
            for call in read_calls
        ))
        list_params = rpc.calls_for("thread/list")[0]["params"]
        self.assertEqual(list_params["sortKey"], "updated_at")
        self.assertEqual(list_params["sortDirection"], "desc")
        self.assertEqual(list_params["limit"], 100)
        active_ids = {
            row["id"] for row in rows if row["status"]["type"] == "active"
        }
        self.assertEqual(active_ids, set(expected))

    def test_reconciliation_reads_missing_ancestor_chain_with_separate_budget(self):
        child_id = self.synthetic_id(100)
        parent_id = self.synthetic_id(101)
        root_id = self.synthetic_id(102)
        threads = {
            child_id: self.thread(
                child_id, "Child", parent_id=parent_id,
                status={"type": "active", "activeFlags": ["waitingOnUserInput"]},
            ),
            parent_id: self.thread(
                parent_id, "Parent", parent_id=root_id,
                status={"type": "notLoaded"},
            ),
            root_id: self.thread(
                root_id, "Root", status={"type": "notLoaded"},
            ),
        }
        rpc = ScriptedRPC(loaded_ids=[child_id], threads=threads)
        reconciler = live.LoadedThreadReconciler()

        rows = reconciler.reconcile(rpc)
        snapshot = live.snapshot_from_rows(rows)

        self.assertEqual(
            [call["params"]["threadId"] for call in rpc.calls_for("thread/read")],
            [child_id, parent_id, root_id],
        )
        child = snapshot["tasks"][0]
        self.assertEqual(child["state"], "waiting_for_input")
        self.assertEqual(child["parent_thread_id"], parent_id)
        self.assertEqual(child["root_thread_id"], root_id)
        self.assertEqual(child["root_title"], "Root")

    def test_ancestor_reads_stop_at_the_separate_fifty_read_budget(self):
        chain = [self.synthetic_id(1_000 + index) for index in range(62)]
        threads = {}
        for index, thread_id in enumerate(chain):
            parent_id = chain[index + 1] if index + 1 < len(chain) else None
            threads[thread_id] = self.thread(
                thread_id,
                "Chain %d" % index,
                parent_id=parent_id,
                status={"type": "active", "activeFlags": []}
                    if index == 0 else {"type": "notLoaded"},
            )
        rpc = ScriptedRPC(loaded_ids=[chain[0]], threads=threads)
        reconciler = live.LoadedThreadReconciler()

        rows = reconciler.reconcile(rpc)

        self.assertIsNotNone(rows)
        self.assertEqual(len(rpc.calls_for("thread/read")), 1 + live.MAX_ANCESTOR_READS)
        self.assertLessEqual(reconciler.last_request_count, live.MAX_CYCLE_REQUESTS)
        self.assertNotIn(chain[51], {row["id"] for row in rows})

    def test_method_not_found_falls_back_once_but_transient_errors_do_not(self):
        thread_id = self.synthetic_id(200)
        row = self.thread(thread_id, "Legacy active")
        unavailable = ScriptedRPC(
            list_rows=[row],
            loaded_error={"code": -32601, "message": "Method not found"},
        )
        reconciler = live.LoadedThreadReconciler()

        first = reconciler.reconcile(unavailable)
        second = reconciler.reconcile(unavailable)

        self.assertIsNotNone(first)
        self.assertIsNotNone(second)
        self.assertEqual(len(unavailable.calls_for("thread/list")), 2)
        self.assertEqual(len(unavailable.calls_for("thread/loaded/list")), 1)
        self.assertEqual(len(unavailable.calls_for("thread/read")), 0)

        retryable = live.LoadedThreadReconciler()
        transient = ScriptedRPC(
            list_rows=[row],
            loaded_error={"code": -32000, "message": "Temporarily unavailable"},
        )
        self.assertIsNone(retryable.reconcile(transient))
        recovered = ScriptedRPC(
            list_rows=[row], loaded_ids=[thread_id], threads={thread_id: row}
        )
        self.assertIsNotNone(retryable.reconcile(recovered))
        self.assertEqual(len(recovered.calls_for("thread/loaded/list")), 1)

    def test_transient_and_malformed_cycles_send_nothing(self):
        thread_id = self.synthetic_id(300)
        row = self.thread(thread_id, "Retain last snapshot")
        configuration = {
            "token": "a" * 64,
            "endpoint_host": "127.0.0.1",
        }
        sent = []

        def sender(_configuration, snapshot):
            sent.append(snapshot)

        reconciler = live.LoadedThreadReconciler()
        good = ScriptedRPC(
            list_rows=[row], loaded_ids=[thread_id], threads={thread_id: row}
        )
        self.assertEqual(
            live.publish_reconciliation(reconciler, good, configuration, sender=sender),
            live.PUBLISHED,
        )
        self.assertEqual(len(sent), 1)

        transient = ScriptedRPC(
            list_rows=[row],
            loaded_error={"code": -32000, "message": "Temporary"},
        )
        self.assertEqual(
            live.publish_reconciliation(
                reconciler, transient, configuration, sender=sender
            ),
            live.RECONCILIATION_FAILED,
        )
        malformed = ScriptedRPC(
            list_rows=[row], loaded_ids=[thread_id], threads={thread_id: []}
        )
        self.assertEqual(
            live.publish_reconciliation(
                reconciler, malformed, configuration, sender=sender
            ),
            live.RECONCILIATION_FAILED,
        )
        failed_read = ScriptedRPC(
            list_rows=[row],
            loaded_ids=[thread_id],
            threads={thread_id: OSError("read failed")},
        )
        self.assertEqual(
            live.publish_reconciliation(
                reconciler, failed_read, configuration, sender=sender
            ),
            live.RECONCILIATION_FAILED,
        )
        self.assertEqual(len(sent), 1)

    def test_offline_publication_keeps_the_normal_poll_cadence_and_last_snapshot(self):
        thread_id = self.synthetic_id(301)
        row = self.thread(thread_id, "Mac is offline")
        rpc = ScriptedRPC(
            list_rows=[row], loaded_ids=[thread_id], threads={thread_id: row}
        )
        reconciler = live.LoadedThreadReconciler()
        previously_published = [{"sequence": 7, "tasks": [{"thread_id": thread_id}]}]
        attempted = []

        def offline_sender(_configuration, snapshot):
            attempted.append(snapshot)
            raise ConnectionRefusedError("Mac is offline")

        result = live.publish_reconciliation(
            reconciler,
            rpc,
            {"token": "a" * 64, "endpoint_host": "127.0.0.1"},
            sender=offline_sender,
        )

        self.assertEqual(result, live.PUBLICATION_FAILED)
        self.assertEqual(live.retry_interval(result), live.POLL_INTERVAL)
        self.assertEqual(len(attempted), 1)
        self.assertEqual(attempted[0]["tasks"][0]["thread_id"], thread_id)
        self.assertEqual(
            previously_published,
            [{"sequence": 7, "tasks": [{"thread_id": thread_id}]}],
        )

    def test_repeated_malformed_and_over_bound_cycles_keep_ten_second_cadence(self):
        thread_id = self.synthetic_id(302)
        row = self.thread(thread_id, "Malformed")
        configuration = {"token": "a" * 64, "endpoint_host": "127.0.0.1"}
        sent = []
        cases = [
            ScriptedRPC(
                list_rows=[row], loaded_ids=[thread_id], threads={thread_id: []}
            ),
            ScriptedRPC(
                loaded_ids=[self.synthetic_id(20_000 + index) for index in range(1_002)],
                page_size=100,
            ),
        ]

        for rpc in cases:
            reconciler = live.LoadedThreadReconciler()
            for _ in range(2):
                result = live.publish_reconciliation(
                    reconciler,
                    rpc,
                    configuration,
                    sender=lambda _configuration, snapshot: sent.append(snapshot),
                )
                self.assertEqual(result, live.RECONCILIATION_FAILED)
                self.assertEqual(live.retry_interval(result), live.POLL_INTERVAL)
        self.assertEqual(sent, [])

    def test_enumeration_and_deadline_fail_closed_at_absolute_bounds(self):
        loaded_ids = [self.synthetic_id(10_000 + index) for index in range(1_002)]
        bounded_rpc = ScriptedRPC(loaded_ids=loaded_ids, page_size=100)
        reconciler = live.LoadedThreadReconciler()

        self.assertIsNone(reconciler.reconcile(bounded_rpc))
        self.assertEqual(len(bounded_rpc.calls_for("thread/loaded/list")), 10)
        self.assertEqual(len(bounded_rpc.calls_for("thread/read")), 0)
        self.assertLessEqual(reconciler.last_request_count, live.MAX_CYCLE_REQUESTS)

        now = [0.0]
        calls = []

        def clock():
            return now[0]

        def slow_call(method, params, deadline):
            calls.append((method, params, deadline))
            now[0] = 2.0
            return {"result": {"data": []}}

        timed = live.LoadedThreadReconciler(cycle_timeout=1, clock=clock)
        self.assertIsNone(timed.reconcile(slow_call))
        self.assertEqual(len(calls), 1)

    def test_rpc_message_work_bound_stops_a_notification_flood(self):
        class NoisyClient:
            def __init__(self):
                self.connection = object()
                self.received = 0

            def send_json(self, _value, deadline=None):
                self.deadline = deadline

            def receive_json(self, deadline=None):
                self.received += 1
                return {"method": "thread/status/changed"}

        client = NoisyClient()
        rpc = live.AppServerRPC(client, clock=lambda: 0)
        rpc.begin_cycle()
        with mock.patch.object(
            live.select, "select", return_value=([client.connection], [], [])
        ):
            with self.assertRaises(TimeoutError):
                rpc.call("thread/list", {}, deadline=1)

        self.assertTrue(rpc.transport_failed)
        self.assertEqual(client.received, live.MAX_CYCLE_MESSAGES + 1)

    def test_sent_snapshot_drops_content_paths_and_remote_metadata(self):
        thread_id = self.synthetic_id(400)
        row = self.thread(thread_id, "Privacy projection")
        rpc = ScriptedRPC(
            list_rows=[row], loaded_ids=[thread_id], threads={thread_id: row}
        )
        reconciler = live.LoadedThreadReconciler()
        sent = []

        self.assertEqual(
            live.publish_reconciliation(
                reconciler,
                rpc,
                {"token": "a" * 64, "endpoint_host": "127.0.0.1"},
                sender=lambda _configuration, snapshot: sent.append(snapshot),
            ),
            live.PUBLISHED,
        )

        encoded = json.dumps(sent[0], sort_keys=True).lower()
        self.assertNotIn("/home/ralf/private", encoded)
        self.assertNotIn("secret prompt", encoded)
        self.assertNotIn("secret transcript", encoded)
        self.assertNotIn("originurl", encoded)
        self.assertNotIn("secret.git", encoded)
        self.assertNotIn("remoteurl", encoded)
        self.assertNotIn("example.invalid", encoded)
        self.assertEqual(sent[0]["tasks"][0]["project_label"], "codex-notch")
        self.assertEqual(
            sent[0]["tasks"][0]["branch"], "codex/loaded-reconciliation"
        )
        methods = {call["method"] for call in rpc.calls}
        self.assertEqual(methods, {"thread/list", "thread/loaded/list", "thread/read"})
        self.assertTrue(all(
            call["params"].get("includeTurns") is False
            for call in rpc.calls_for("thread/read")
        ))


if __name__ == "__main__":
    unittest.main()
