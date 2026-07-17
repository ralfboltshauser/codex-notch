import importlib.util
import json
from pathlib import Path
import unittest


SCRIPT = Path(__file__).parents[1] / "codex_notch_live.py"
SPEC = importlib.util.spec_from_file_location("codex_notch_live_context", SCRIPT)
live = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(live)


class LinuxActiveTaskContextTests(unittest.TestCase):
    def setUp(self):
        live.sequence = 0
        live.generation = "11111111-1111-4111-8111-111111111111"

    def test_nested_subagents_share_root_and_only_send_display_context(self):
        root_id = "019f5d4f-3a8d-76c0-8c2d-19451190e020"
        child_id = "019f5d4f-3a8d-76c0-8c2d-19451190e021"
        grandchild_id = "019f5d4f-3a8d-76c0-8c2d-19451190e022"
        rows = [
            {
                "id": root_id,
                "name": "Ship Codex Notch",
                "status": {"type": "active", "activeFlags": []},
                "parentThreadId": None,
                "cwd": "/home/ralf/private/codex-notch",
                "gitInfo": {
                    "branch": "codex/attention-workflow",
                    "originUrl": "git@github.com:private/secret.git",
                },
            },
            {
                "id": child_id,
                "name": "Implement context",
                "status": {"type": "active", "activeFlags": []},
                "parentThreadId": root_id,
                "cwd": "/home/ralf/private/codex-notch",
                "gitInfo": {"branch": "codex/attention-workflow"},
                "agentNickname": "Atlas",
                "agentRole": "worker",
            },
            {
                "id": grandchild_id,
                "name": "Verify privacy",
                "status": {"type": "active", "activeFlags": ["waitingOnUserInput"]},
                "parentThreadId": child_id,
                "cwd": "/home/ralf/private/codex-notch",
                "gitInfo": {"branch": "codex/attention-workflow"},
            },
        ]

        snapshot = live.snapshot_from_rows(rows)

        self.assertEqual(len(snapshot["tasks"]), 3)
        child = next(task for task in snapshot["tasks"] if task["thread_id"] == child_id)
        grandchild = next(task for task in snapshot["tasks"] if task["thread_id"] == grandchild_id)
        self.assertEqual(child["root_thread_id"], root_id)
        self.assertEqual(grandchild["root_thread_id"], root_id)
        self.assertEqual(grandchild["root_title"], "Ship Codex Notch")
        self.assertEqual(child["project_label"], "codex-notch")
        self.assertEqual(child["branch"], "codex/attention-workflow")
        self.assertEqual(child["agent_nickname"], "Atlas")
        self.assertEqual(child["agent_role"], "worker")

        encoded = json.dumps(snapshot, sort_keys=True)
        self.assertNotIn("/home/ralf/private", encoded)
        self.assertNotIn("originUrl", encoded)
        self.assertNotIn("secret.git", encoded)

    def test_missing_parent_still_produces_a_stable_rollup_key(self):
        parent_id = "019f5d4f-3a8d-76c0-8c2d-19451190e030"
        child_id = "019f5d4f-3a8d-76c0-8c2d-19451190e031"
        snapshot = live.snapshot_from_rows([{
            "id": child_id,
            "name": "Detached child",
            "status": {"type": "active", "activeFlags": []},
            "parentThreadId": parent_id,
        }])

        self.assertEqual(snapshot["tasks"][0]["root_thread_id"], parent_id)
        self.assertNotIn("root_title", snapshot["tasks"][0])


if __name__ == "__main__":
    unittest.main()
