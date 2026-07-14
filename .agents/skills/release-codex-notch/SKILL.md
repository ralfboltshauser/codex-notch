---
name: release-codex-notch
description: Prepare, verify, publish, and diagnose Codex Notch releases through the repository's Linux preflight, GitHub pull-request CI, tag-triggered signed macOS workflow, notarization, Sparkle appcast, and GitHub Release. Use when asked to release, publish, cut, tag, version-bump, validate a release candidate, monitor release CI, or investigate a failed Codex Notch release.
---

# Release Codex Notch

Treat the repository and current GitHub state as ground truth. Never infer that
uncommitted work, a PR branch, `main`, a tag, and a published release contain the
same code.

## Establish the release state

Run from the repository root. Read these files before changing anything:

- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`
- `prepare-release.sh`
- `build-macos-app.sh`
- `AppResources/Info.plist`
- `Package.swift`
- `docs/update-pipeline.md`

Then inspect the independent states:

```sh
git status --short
git branch --show-current
git remote -v
git fetch --tags --prune origin
git rev-parse HEAD
git rev-parse origin/main
git log --oneline --left-right origin/main...HEAD
git tag --sort=-version:refname | head -20
gh auth status
gh pr list --state open
gh workflow list --all
gh run list --limit 20
gh release list --limit 20
gh secret list --app actions
```

Verify that the origin is `ralfboltshauser/codex-notch`. List secret names only;
never request, print, or copy secret values.

Stop and report the exact conflict when:

- the worktree contains changes whose release scope is unknown;
- intended files are untracked or absent from the release candidate;
- another release PR or release workflow is active;
- the requested version or tag already exists;
- the candidate does not descend from current `origin/main`.

Never reset, clean, stash, overwrite, or switch away from user changes. Use a
separate worktree when isolation is needed.

## Define the candidate

Agree on the semantic version and intended change set. Derive the previous
version from both Git tags and GitHub Releases; do not trust README examples.
Require `MAJOR.MINOR.PATCH`, and increment `CFBundleVersion` monotonically.

Audit what will ship:

```sh
git diff --stat origin/main...HEAD
git diff --name-status origin/main...HEAD
git log --oneline origin/main..HEAD
```

Ensure every intended change is committed to the release PR. A tag cannot
contain dirty or untracked files.

Update both version fields in `AppResources/Info.plist`:

- On macOS, run `./prepare-release.sh VERSION`.
- On Ubuntu, use `apply_patch` to set `CFBundleShortVersionString` and increment
  `CFBundleVersion`; `prepare-release.sh` intentionally requires macOS.

Validate the plist portably:

```sh
VERSION=0.0.0 python3 - <<'PY'
import os
import plistlib

with open("AppResources/Info.plist", "rb") as file:
    info = plistlib.load(file)
assert info["CFBundleShortVersionString"] == os.environ["VERSION"]
assert int(info["CFBundleVersion"]) > 0
print(info["CFBundleShortVersionString"], info["CFBundleVersion"])
PY
```

Replace `0.0.0` with the selected version.

## Run the Ubuntu preflight

Mirror the Linux CI job exactly, then add Swift parsing as an Ubuntu-only early
signal:

```sh
python3 -m unittest discover -s Tests/LinuxHookTests -v
for script in *.sh; do sh -n "$script"; done
python3 -m py_compile remote/codex_notch_remote.py remote/codex_notch_live.py
find Sources Tests -name '*.swift' -print0 | xargs -0 swiftc -frontend -parse
git diff --check
```

Do not claim that Swift parsing validates AppKit types or linking. The macOS CI
job is authoritative for `swift test` and `./build-macos-app.sh`.

## Put the candidate through PR CI

Create or update a `codex/release-VERSION` branch and PR. Keep unrelated local
changes out of it. Before any push, show the proposed commit scope. Before merge,
show the PR URL and check state.

Watch every PR check, not only “required” checks:

```sh
gh pr checks PR --watch --fail-fast
gh pr checks PR
```

Require successful `linux` and `macos` jobs. Do not rely on branch protection;
re-check repository rules because `main` has historically been unprotected.

For a failure, identify the exact run and inspect only failed logs first:

```sh
gh run list --branch BRANCH --workflow CI --limit 10
gh run view RUN_ID --log-failed
```

Fix the cause in a new commit and let new CI run. Rerun an old job only for a
confirmed transient infrastructure failure.

Merge only after the user has authorized it and every check passes. Follow the
repository's squash-merge convention unless the user requests otherwise:

```sh
gh pr merge PR --squash --delete-branch
```

## Gate the exact merged commit

Capture the PR's squash-merge commit, then fetch again. The only releasable
commit is that exact merge SHA—not the former PR head and not a newer
`origin/main` tip that may contain unaudited work:

```sh
RELEASE_SHA=$(gh pr view PR --json mergeCommit --jq '.mergeCommit.oid')
test -n "$RELEASE_SHA"
git fetch --tags --prune origin
git cat-file -e "$RELEASE_SHA^{commit}"
git merge-base --is-ancestor "$RELEASE_SHA" origin/main
gh run list --workflow CI --commit "$RELEASE_SHA" --event push --limit 10 \
  --json databaseId,headBranch,status,conclusion,url
```

Select the run whose `headBranch` is `main`, then require it to succeed:

```sh
gh run watch CI_RUN_ID --exit-status
```

Verify the version from that exact commit, not the working tree:

```sh
git show "$RELEASE_SHA":AppResources/Info.plist | VERSION=0.0.0 python3 -c \
  'import os,plistlib,sys; p=plistlib.loads(sys.stdin.buffer.read()); assert p["CFBundleShortVersionString"] == os.environ["VERSION"]; print(p["CFBundleShortVersionString"], p["CFBundleVersion"])'
test -z "$(git tag -l "vVERSION")"
test -z "$(git ls-remote --tags origin "refs/tags/vVERSION")"
```

Confirm `vVERSION` is absent locally and remotely. Immediately before publishing,
summarize the version, `RELEASE_SHA`, merged PR, local checks, PR checks, main CI,
and expected tag. Obtain explicit confirmation unless the current request already
unambiguously authorizes publication.

## Publish through the tag workflow

Use the repository's lightweight-tag convention and tag the verified SHA:

```sh
git tag "vVERSION" "$RELEASE_SHA"
git push origin "refs/tags/vVERSION"
```

Do not use `gh workflow run` for Release. The workflow has a `push.tags: v*`
trigger and no `workflow_dispatch`; pushing the tag is the release operation.

Find and watch the Release run for the exact tag and SHA:

```sh
gh run list --workflow Release --commit "$RELEASE_SHA" --event push --limit 10 \
  --json databaseId,headBranch,status,conclusion,url
gh run watch RELEASE_RUN_ID --exit-status
```

Read `references/release-contract.md` before diagnosing a failure or declaring
publication complete.

## Verify publication

Require a non-draft, non-prerelease GitHub Release with exactly these kinds of
assets:

- `CodexNotch-VERSION.zip`
- `CodexNotch-VERSION.zip.sha256`
- `appcast.xml`

Inspect and checksum them:

```sh
gh release view "vVERSION" --json tagName,isDraft,isPrerelease,assets,url
DIR=$(mktemp -d)
gh release download "vVERSION" --dir "$DIR"
(cd "$DIR" && shasum -a 256 -c "CodexNotch-VERSION.zip.sha256")
curl -fsSIL https://github.com/ralfboltshauser/codex-notch/releases/latest/download/appcast.xml
```

Report the release URL, tag, commit SHA, workflow URL, asset names, and checksum
result. Do not say “released” merely because the tag exists.

## Handle failures conservatively

Never force-move or silently delete a published tag. If publication fails:

1. Record the failing step and run URL.
2. Determine whether the failure is transient, secret/configuration-related, or
   encoded in the tagged commit.
3. Rerun the same workflow only when the same commit can succeed unchanged, such
   as after repairing a secret or transient service failure.
4. If code or workflow changes are required, stop and ask whether to consume a
   new patch version. Do not rewrite release history without explicit approval.
