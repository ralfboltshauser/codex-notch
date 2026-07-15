# Recovery audit for 0.4.16

This audit was performed before preparing 0.4.16. Its purpose was to distinguish
unreleased work from old worktree state, squash-merged branches, rebased commits,
and genuinely unreachable Git objects.

## Ground truth

- The last published release at audit start was `v0.4.15` at
  `c3e33b499b163bef3d5c902ae8a415b3f23a99c5`.
- The only open pull request was #33, `codex/host-health-badge`.
- There were 17 pre-existing linked worktrees, two of them dirty.
- The local `main` worktree was still at the old 0.3.8-era commit
  `efd8b7a8f203845bcf517d030c7f02243a777d5a`; it was not release authority.
- The 0.4.15 release archive was downloaded and inspected. Its binary contains
  `CodexUsageMonitor`, the rate-limit request, usage-history storage, and the
  weekly forecast UI strings.

## Branch accounting

The following branch groups were already represented by merged pull requests on
`main`:

- Update, signing, pairing, notch-shape, and release foundations:
  `agent/tailscale-completion-sync`, `codex/signing-preflight`,
  `codex/restore-notch-shoulders`, `codex/fix-remote-pairing-readiness`,
  `codex/release-0.3.1`, and `codex/release-0.3.2`.
- Product releases and fixes:
  `codex/release-0.3.10`, `codex/release-0.3.11`,
  `codex/release-0.4.0` through `codex/release-0.4.8`,
  `codex/release-0.4.9-menu-bar-header`,
  `codex/release-0.4.10-notch-hover`,
  `codex/release-0.4.11-changelog`,
  `codex/release-0.4.12-changelog-fix`,
  `codex/release-0.4.13-reconcile`,
  `codex/release-0.4.14-structure-fix`, and
  `codex/frozen-status-active-header`.
- Weekly usage: `codex/weekly-limit` was merged by #12 and then expanded by #23
  with persisted history and forecasting.
- Live theme previews: `codex/theme-live-notch` was closed directly, but its tip
  is an ancestor of `codex/release-0.4.3`, which was merged by #19.
- Repository reorganization: `codex/release-0.4.13-monorepo` points at the
  already-merged 0.4.12 commit; the completed reorganization shipped through
  #30 and #31.
- Shortcut-lock intermediates `codex/release-0.4.7`,
  `codex/release-0.4.7-ci-fix`, and
  `codex/release-0.4.7-shortcut-lock` shipped through #23 and #24.

The only branch with intentional product changes not yet on `main` was
`codex/host-health-badge` (#33). Its host-health badge, direct Connections route,
and header cleanup were integrated into the 0.4.16 recovery candidate.

## Dirty worktrees

`/home/ralf/prj/exploration/codex-notch` contained an unfinished directory move
on top of an old local `main`. Its app metadata was 0.3.11 (build 14), and it
omitted later shipped files such as `CodexUsageHistory.swift`,
`NotchHoverMonitor.swift`, and the bundled changelog. Every differing app source
was compared with current `origin/main`. The only unique HookSupport variant
removed current owned-hook detection, while its unique test snapshot deleted
newer coverage. Copying this tree would regress the app.

`/home/ralf/prj/exploration/codex-notch-release` contained a staged 0.4.13
reorganization. Its remaining unique blobs were documentation/formatting
variants, older 0.4.13 changelog assertions, and path edits already superseded by
the merged 0.4.14 repository structure. It contained no newer product behavior.

## Reflog, stash, and unreachable-object accounting

All unreachable commits were inspected. Feature commits for uninstall, nerd
shortcuts, settings version, motion polish, shortcut locking, and the Frozen
indicator correspond to merged PRs #8, #9, #10, #11, #24, and #32.

Two unreachable stash commits contained early WIP versions of uninstall and
weekly usage. The later named commits added substantially more implementation
and tests and were merged by #8 and #12; weekly usage was expanded again by #23.
No stash-only behavior remained to recover.

## Feature verification

Current source and tests retain themes, sounds, active-task shortcuts, Do Not
Disturb, live theme previews, stable settings geometry, shortcut-order freezing,
menu-bar placement, hover opening, changelog rendering, persistent event
openings, weekly usage history/forecasting, and the Active/Frozen indicator.

The weekly usage failure reported against 0.4.15 was not a missing source merge.
The acquisition layer discarded executable, protocol, and parsing errors and the
overlay hid the entire surface when it received no value. In 0.4.16, loading and
failure states remain visible, failure details are available on hover, retry is
direct, and per-user Applications folders are included in Codex discovery.

Branches and worktrees are eligible for deletion only after the exact 0.4.16
merge commit passes CI and the signed release is published and verified.
