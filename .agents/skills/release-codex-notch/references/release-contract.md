# Codex Notch release contract

Read this reference before diagnosing a release failure or declaring a release
complete. Re-read the live workflow files because they override this snapshot.

## Source hierarchy

Use these sources in descending order of authority:

1. The candidate commit's `.github/workflows/ci.yml` and
   `.github/workflows/release.yml`.
2. The exact GitHub run, jobs, and logs for that commit.
3. Repository scripts and `apps/macos/AppResources/Info.plist` from that commit.
4. This reference and `docs/update-pipeline.md`.
5. README examples, which may show an old version.

## CI contract

The CI workflow runs for pushes and pull requests.

- `linux` runs `make check-linux`, which exercises the Ubuntu app tests,
  repository-tool tests, shell syntax, Python compilation, and changelog
  validation.
- `macos` runs `make test-macos` and builds the complete app bundle with
  `scripts/build-macos-app.sh` on a macOS runner.

A Linux workstation cannot validate AppKit type checking, Swift linking, app
bundle construction, Sparkle framework assembly, code signing, or Gatekeeper.
Treat local Swift parsing only as a syntax preflight.

Because CI also runs on tag pushes, a successful tag CI is useful corroboration
but is too late to be the release gate. Require successful PR CI and successful
push CI for the exact merged `main` SHA before creating the tag.

## Release contract

The Release workflow accepts only `vMAJOR.MINOR.PATCH` tag pushes. It requires:

- the tag SHA to be an ancestor of `origin/main`;
- the tag version to equal `CFBundleShortVersionString`;
- the newest bundled changelog entry to equal that version;
- `MACOS_CERTIFICATE_P12` and `MACOS_CERTIFICATE_PASSWORD`;
- `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD`;
- `SPARKLE_PRIVATE_KEY` matching `SUPublicEDKey` in the plist.

The workflow performs these steps in order:

1. Validate tag, main ancestry, version, and secret presence.
2. Validate the bundled changelog and matching release entry.
3. Import the Developer ID Application certificate into an ephemeral keychain.
4. Build and sign the app, helper, and Sparkle components.
5. Verify the Apple team identity and arm64 architecture.
6. Submit to Apple notarization, staple the ticket, validate it, and run
   Gatekeeper assessment.
7. Generate and verify the Ed25519-signed Sparkle appcast and archive signature.
8. Write the archive SHA-256 checksum.
9. Render the matching bundled changelog entry and publish it with the GitHub
   Release and its three assets.

The stable Sparkle feed is:

```text
https://github.com/ralfboltshauser/codex-notch/releases/latest/download/appcast.xml
```

`scripts/release-macos.sh` is a manual macOS notarization path. It is not the normal
GitHub/Sparkle publication path and does not replace the tag workflow.

## Failure map

- **Validate release configuration:** check the tag format, version mismatch,
  ancestry, or missing secret names.
- **Import Developer ID certificate:** check the base64 `.p12`, its password,
  certificate expiry, and Developer ID Application identity.
- **Build signed app:** inspect Swift tests/build inputs, resources, Sparkle
  assembly, and nested signing order.
- **Verify signing identity and architecture:** check `APPLE_TEAM_ID`, signing
  identity, or unexpected non-arm64 products.
- **Notarize and staple:** inspect Apple credentials, app-specific password,
  notarization response, entitlements, and Apple service status.
- **Generate signed Sparkle appcast:** check the private seed/public key pairing,
  Sparkle tools, archive signature, feed signature, and asset paths.
- **Publish GitHub release:** check `contents: write`, GitHub service state,
  duplicate tag/release, and asset creation.

Use `gh run view RUN_ID --log-failed` before reading full logs. Do not expose
secret values in diagnostics.

## GitHub behavior relied upon

- A push matching a `tags` filter triggers the workflow:
  https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#running-your-workflow-only-when-a-push-of-specific-tags-occurs
- `gh workflow run` requires `workflow_dispatch`:
  https://cli.github.com/manual/gh_workflow_run
- `gh pr checks --watch` monitors checks associated with a PR:
  https://cli.github.com/manual/gh_pr_checks
- `gh run list --commit` finds runs for an exact SHA:
  https://cli.github.com/manual/gh_run_list
- `gh run watch --exit-status` fails the command when the run fails:
  https://cli.github.com/manual/gh_run_watch

Re-check branch rules before every release. At the time this skill was created,
`main` had no GitHub branch protection, so the workflow must enforce all gates
procedurally rather than assuming GitHub blocks an unsafe merge.
