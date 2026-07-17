import copy
import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "changelog.py"
SPEC = importlib.util.spec_from_file_location(
    "codex_notch_changelog", SCRIPT
)
CHANGELOG = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHANGELOG)


class ChangelogTests(unittest.TestCase):
    def setUp(self):
        self.document, self.info = CHANGELOG.load_inputs()

    def test_bundled_changelog_matches_app_version_and_renders_release_notes(self):
        releases = CHANGELOG.validate_document(self.document, self.info)

        self.assertEqual(releases[0]["version"], "0.4.25")
        notes = CHANGELOG.markdown_for(releases, "0.4.25")
        self.assertIn(releases[0]["title"], notes)
        self.assertIn(f"- {releases[0]['changes'][0]}", notes)

    def test_validation_rejects_missing_release_entry(self):
        document = copy.deepcopy(self.document)
        document["releases"] = document["releases"][1:]

        with self.assertRaisesRegex(CHANGELOG.ChangelogError, "does not match"):
            CHANGELOG.validate_document(document, self.info)

    def test_validation_rejects_duplicate_or_empty_release_content(self):
        duplicate = copy.deepcopy(self.document)
        duplicate["releases"].insert(1, copy.deepcopy(duplicate["releases"][0]))
        with self.assertRaisesRegex(CHANGELOG.ChangelogError, "Duplicate"):
            CHANGELOG.validate_document(duplicate, self.info)

        empty = copy.deepcopy(self.document)
        empty["releases"][0]["changes"] = []
        with self.assertRaisesRegex(CHANGELOG.ChangelogError, "1 to 6"):
            CHANGELOG.validate_document(empty, self.info)
