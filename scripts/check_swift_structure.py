#!/usr/bin/env python3
import argparse
from dataclasses import dataclass
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_POLICIES = (
    (Path("apps/macos/Sources"), 900),
    (Path("apps/macos/Tests"), 650),
)


@dataclass(frozen=True)
class SwiftFileViolation:
    path: Path
    line_count: int
    maximum: int


def count_lines(path):
    with Path(path).open(encoding="utf-8") as file:
        return sum(1 for _ in file)


def find_violations(repository_root=REPOSITORY_ROOT, policies=DEFAULT_POLICIES):
    root = Path(repository_root)
    violations = []
    for relative_directory, maximum in policies:
        directory = root / relative_directory
        for path in sorted(directory.rglob("*.swift")):
            line_count = count_lines(path)
            if line_count > maximum:
                violations.append(
                    SwiftFileViolation(
                        path=path.relative_to(root),
                        line_count=line_count,
                        maximum=maximum,
                    )
                )
    return violations


def main():
    parser = argparse.ArgumentParser(
        description="Keep production and test Swift files within reviewable bounds"
    )
    parser.add_argument("--repository-root", type=Path, default=REPOSITORY_ROOT)
    args = parser.parse_args()

    violations = find_violations(args.repository_root)
    if violations:
        for violation in violations:
            print(
                f"{violation.path}: {violation.line_count} lines "
                f"(maximum {violation.maximum})"
            )
        raise SystemExit(
            "Swift structure check failed. Split responsibilities before adding more code."
        )
    print("Swift source and test files stay within their component size limits.")


if __name__ == "__main__":
    main()
