import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "check_swift_structure.py"
SPEC = importlib.util.spec_from_file_location("codex_notch_structure", SCRIPT)
STRUCTURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STRUCTURE)


class SwiftStructureTests(unittest.TestCase):
    def test_accepts_files_at_the_configured_limit(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "Sources" / "Component.swift"
            source.parent.mkdir(parents=True)
            source.write_text("line\n" * 3, encoding="utf-8")

            violations = STRUCTURE.find_violations(
                root,
                policies=((Path("Sources"), 3),),
            )

            self.assertEqual(violations, [])

    def test_reports_every_oversized_file_with_its_policy(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "Sources" / "Large.swift"
            test = root / "Tests" / "LargeTests.swift"
            source.parent.mkdir(parents=True)
            test.parent.mkdir(parents=True)
            source.write_text("line\n" * 4, encoding="utf-8")
            test.write_text("line\n" * 6, encoding="utf-8")

            violations = STRUCTURE.find_violations(
                root,
                policies=((Path("Sources"), 3), (Path("Tests"), 5)),
            )

            self.assertEqual(
                [(str(item.path), item.line_count, item.maximum) for item in violations],
                [("Sources/Large.swift", 4, 3), ("Tests/LargeTests.swift", 6, 5)],
            )
