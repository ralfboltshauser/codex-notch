import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).parents[1] / "codex_notch_live.py"
SPEC = importlib.util.spec_from_file_location("codex_notch_live", SCRIPT)
live = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(live)


class LinuxLiveObserverTests(unittest.TestCase):
    def setUp(self):
        live.sequence = 0
        live.generation = "11111111-1111-4111-8111-111111111111"

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


if __name__ == "__main__":
    unittest.main()
