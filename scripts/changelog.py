#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CHANGELOG = ROOT / "apps/macos/Sources/CodexNotchApp/Resources/Changelog.json"
DEFAULT_PLIST = ROOT / "apps/macos/AppResources/Info.plist"
VERSION_PATTERN = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


class ChangelogError(ValueError):
    pass


def version_tuple(value):
    match = VERSION_PATTERN.fullmatch(value) if isinstance(value, str) else None
    if not match:
        raise ChangelogError(f"Invalid semantic version: {value!r}")
    return tuple(int(part) for part in match.groups())


def load_inputs(changelog_path=DEFAULT_CHANGELOG, plist_path=DEFAULT_PLIST):
    with Path(changelog_path).open(encoding="utf-8") as file:
        document = json.load(file)
    with Path(plist_path).open("rb") as file:
        info = plistlib.load(file)
    return document, info


def validate_document(document, info):
    if not isinstance(document, dict) or set(document) != {"releases"}:
        raise ChangelogError("Changelog root must contain only 'releases'")
    releases = document["releases"]
    if not isinstance(releases, list) or not releases:
        raise ChangelogError("Changelog must contain at least one release")

    seen = set()
    previous = None
    for index, release in enumerate(releases):
        if not isinstance(release, dict) or set(release) != {
            "version", "date", "title", "changes"
        }:
            raise ChangelogError(f"Release {index + 1} has an invalid schema")
        version = release["version"]
        parsed_version = version_tuple(version)
        if parsed_version in seen:
            raise ChangelogError(f"Duplicate changelog version: {version}")
        if previous is not None and parsed_version >= previous:
            raise ChangelogError("Changelog releases must be newest first")
        seen.add(parsed_version)
        previous = parsed_version

        try:
            dt.date.fromisoformat(release["date"])
        except (TypeError, ValueError) as error:
            raise ChangelogError(f"Release {version} has an invalid ISO date") from error
        if not isinstance(release["title"], str) or not release["title"].strip():
            raise ChangelogError(f"Release {version} needs a user-facing title")
        changes = release["changes"]
        if not isinstance(changes, list) or not 1 <= len(changes) <= 6:
            raise ChangelogError(f"Release {version} needs 1 to 6 changes")
        if any(not isinstance(change, str) or not change.strip() for change in changes):
            raise ChangelogError(f"Release {version} contains an empty change")

    plist_version = info.get("CFBundleShortVersionString")
    if releases[0]["version"] != plist_version:
        raise ChangelogError(
            f"Newest changelog version {releases[0]['version']} does not match "
            f"Info.plist {plist_version}"
        )
    return releases


def markdown_for(releases, version):
    release = next((item for item in releases if item["version"] == version), None)
    if release is None:
        raise ChangelogError(f"No changelog entry exists for {version}")
    lines = [release["title"], ""]
    lines.extend(f"- {change}" for change in release["changes"])
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Validate and render Codex Notch changelog data")
    parser.add_argument("--changelog", type=Path, default=DEFAULT_CHANGELOG)
    parser.add_argument("--plist", type=Path, default=DEFAULT_PLIST)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate")
    markdown = subparsers.add_parser("markdown")
    markdown.add_argument("version")
    args = parser.parse_args()

    try:
        document, info = load_inputs(args.changelog, args.plist)
        releases = validate_document(document, info)
        if args.command == "markdown":
            print(markdown_for(releases, args.version), end="")
        else:
            print(f"Changelog matches {releases[0]['version']} ({len(releases)} releases).")
    except (ChangelogError, json.JSONDecodeError, OSError, plistlib.InvalidFileException) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
