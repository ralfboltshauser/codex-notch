# Codex Notch

Codex Notch is a native macOS overlay for active and finished Codex turns. It works
entirely on one Mac, and can also receive completions from Ubuntu hosts over an
existing Tailscale network. There is no hosted relay, account, or public port.

## How it works

Active tasks come from Codex App Server's runtime status rather than guessed
process or transcript state. Codex Notch connects read-only to the local Unix
WebSocket, keeps the latest full snapshot in memory, and shows running tasks as
well as tasks waiting for approval or input. Active tasks never auto-open the
notch. If the observer disconnects, rows first show that state and then expire;
live snapshots are never queued or replayed.

### Mac-only

The bundled `CodexNotchHook` is registered as a Codex `Stop` hook. It writes a
small JSON event atomically to:

```text
~/Library/Application Support/Codex Notch/inbox/
```

The app monitors that directory, persists the event, and shows it in the
overlay. Opening an item uses the validated local `codex://threads/<uuid>` deep
link. No network process is involved.

The app also starts the installed Codex CLI's local `app-server` briefly to read
the authenticated account's rolling rate-limit snapshot. The seven-day window
is shown as remaining capacity, recent usage, reset time, and a local pace
forecast in the notch. Codex exposes this value as a whole percentage, so Codex
Notch does not invent sub-percent precision: it checks every 15 minutes (and
when the notch opens), records percentage changes plus hourly flat checkpoints,
and waits for at least one hour and a two-point change before estimating when
capacity will run out. Reset-crossing forecasts account for the one-point
measurement boundary. Eight weeks of timestamp, percentage, and reset metadata
are kept locally in a user-only file; prompts and credentials are never read or
stored.

### Ubuntu to Mac

The Mac app pairs an Ubuntu host through an SSH alias from `~/.ssh/config`. It
uploads the Python publisher, generates a 256-bit token, and gives the publisher
the Mac's Tailscale IPv4 address. The Ubuntu hook writes every completion to a
durable outbox before attempting delivery. A separate systemd user service
observes that host's local App Server and sends replace-only active snapshots;
its failures cannot block the completion hook.

Delivery uses a length-prefixed JSON message on TCP port `47391` over Tailscale.
The Mac authenticates the token, persists the event, and only then acknowledges
it. A systemd user timer retries queued events every 30 seconds; the Mac also
asks each paired host to flush after launch and wake. The queue keeps at most 500
events and expires undelivered events after seven days.

Opening a local or remote item uses Codex's validated
`codex://threads/<uuid>` deep link.

## Requirements

- macOS 13 or later
- Swift 5.10 or later when building from source
- Codex CLI on each machine that runs Codex
- Python 3 on Ubuntu
- Tailscale and key-based SSH for remote pairing

Tailscale is optional when all Codex sessions run on the Mac.

## Install on macOS

```sh
git clone https://github.com/ralfboltshauser/codex-notch.git
cd codex-notch
./scripts/install-native-macos.sh
```

The app opens its setup window. Install the local hook, then use Codex `/hooks`
once to review and trust `Saving completion to Codex Notch`.

To add Ubuntu, enter its SSH alias in **Connections** and choose **Pair**. The
app opens a remote Codex session so you can review and trust `Queueing completion
for Codex Notch` there as well.

The notch summarizes all paired hosts in one compact status badge. **Connections**
shows the result for each host and can refresh it manually. A working result
verifies the remote publisher, Codex hook registration, SSH reachability, and
an authenticated ping back to the Mac receiver. Current publishers also report
an untrusted hook as needing attention.

### Nerd shortcuts

These global shortcuts follow the Swiss German keyboard layout. Hold
<kbd>Control</kbd>+<kbd>Shift</kbd>, then press:

| Key | Action |
| --- | --- |
| `H` | Toggle the notch |
| `R` | Show or hide active tasks |
| `J`, `K`, `L`, `Ö` | Open tasks 1–4 |
| `U`, `I`, `O`, `P` | Open tasks 5–8 |
| `N`, `M` | Open tasks 9–10 |

The existing number-key shortcuts remain available.
While Control and Shift are held with the notch open, each task number
changes to its corresponding nerd-key letter and switches back on release.
The visible task order and every shortcut target are frozen for the duration;
the header shows `LOCKED`, and queued task, usage, update, and connection changes
are applied only after both modifiers are released.
While the notch is open, <kbd>Command</kbd>+<kbd>,</kbd> opens Settings. The
shortcut is released back to the foreground app as soon as the notch closes.

Under **Settings → Themes**, choose from six deep-color themes. Hovering a
theme previews it live across Settings and the real open notch; clicking keeps
the choice across launches. The hardware-facing neck remains true black so
every palette still blends into a MacBook display notch.

Under **Settings → Sounds**, choose from six short completion tones or select
**No Sound**. A choice previews immediately and is remembered across launches.
Sounds play only for newly accepted local or remote Stop-hook events; opening the
notch manually stays quiet.

Under **Settings → Tasks**, active task display can be disabled without stopping
the observer. Keeping the in-memory snapshot hot makes re-enabling immediate.
The same `⌃⇧R` shortcut is shown beside the active-task control in the notch.
The independent **Do Not Disturb** switch keeps completed tasks and available
updates in the notch without opening it automatically. Manual shortcuts and the
selected completion sound continue to work; macOS Focus is not read or changed.

Choose **Check for Updates** at the bottom of Settings to ask Sparkle for the
latest signed release immediately.

To remove Codex Notch, open **Connections** and choose **Uninstall Codex Notch…**.
The app first removes and verifies its hooks, retry services, configuration, and
queued events on every paired Ubuntu host. It then removes the local hook and
hook backup, login registration, pairing credentials, app data, and app bundle
from the Mac. If a remote host cannot be reached, the Mac installation is kept
so the cleanup can be retried without forgetting that host.

## Manual Ubuntu install

Normal pairing is initiated by the Mac app. For development, the publisher can
also be installed manually with values generated by a trusted Mac pairing:

```sh
./scripts/install-remote-linux.sh MAC_TAILSCALE_IP 64_HEX_TOKEN HOST_LABEL HOST_ID
```

Uninstall it with:

```sh
./scripts/uninstall-remote-linux.sh
```

## Security and data

- The receiver binds only to the Mac's detected Tailscale IPv4 address.
- Every remote host gets a separate random token stored in a user-only `0600`
  file under Codex Notch's Application Support directory. The receiver loads
  tokens into memory at launch, so accepting a completion never invokes a
  credential UI or blocks on Keychain access.
- Remote messages cannot provide a URL or command. Thread IDs must be UUIDs,
  and the app constructs the local or SSH action itself.
- Weekly usage comes from Codex's local app-server protocol. Codex Notch does
  not inspect auth files, browser storage, or terminal output. Its local usage
  history contains only timestamps, whole remaining percentages, and reset
  timestamps, and is removed with the rest of the app data during uninstall.
- Completion events contain only thread ID, turn ID, title, source identity, and
  timestamp. Active snapshots contain only thread ID, title, display state, and
  timestamp.
  Working directories, prompts, transcripts, and model output are not sent.
- Delivery is at least once. Content-derived event IDs make retries idempotent.
- Hook installation merges with existing `hooks.json` entries and creates a
  backup instead of replacing unrelated hooks.

Anyone with access to the Ubuntu account can read that host's pairing token.
Tailscale access controls should still restrict which tailnet devices can reach
the Mac.

## Development

Platform code is kept under `apps/macos` and `apps/linux`; repository-wide
build, install, and release entry points live under `scripts`.

Run Ubuntu tests on Linux or macOS:

```sh
make check-linux
```

Run the full Swift suite on macOS:

```sh
make test-macos
```

`make build-macos` creates an ad-hoc-signed development app. For a build that
friends can open without bypassing Gatekeeper, set a Developer ID identity and
notarytool profile, then run:

```sh
CODE_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)' \
NOTARY_PROFILE='codex-notch-notary' \
./scripts/release-macos.sh
```

The notarized archive is written to `.build/dist/CodexNotch.zip`.

## Updates

Codex Notch uses Sparkle 2.9.4 with a signed appcast hosted as a GitHub Release
asset. The app probes the feed silently every six hours. When a newer signed
version exists, a green download icon appears in the notch; selecting it opens
Sparkle's verified install flow. Update archives are checked with both Apple
code signing and a dedicated Ed25519 signature. Feed metadata is signed too,
and each archive is verified before extraction.

The release workflow needs these GitHub Actions secrets:

- `MACOS_CERTIFICATE_P12`: base64-encoded Developer ID Application certificate
- `MACOS_CERTIFICATE_PASSWORD`: password protecting the `.p12`
- `APPLE_ID`: Apple ID used for notarization
- `APPLE_TEAM_ID`: Apple Developer team ID
- `APPLE_APP_PASSWORD`: app-specific Apple ID password
- `SPARKLE_PRIVATE_KEY`: base64 Sparkle private seed

`SPARKLE_PRIVATE_KEY` is configured for this repository. Its local recovery
copy is stored outside Git at
`~/.config/codex-notch/sparkle_private_key`; back it up in a password manager.

To publish a release after the Apple secrets are configured:

```sh
edit apps/macos/Sources/CodexNotchApp/Resources/Changelog.json
./scripts/prepare-release.sh 0.4.13
git add apps/macos/AppResources/Info.plist \
  apps/macos/Sources/CodexNotchApp/Resources/Changelog.json
git commit -m 'Prepare 0.4.13 release'
git tag v0.4.13
git push origin main v0.4.13
```

The tag workflow builds and signs the complete app, notarizes and staples it,
generates an EdDSA-signed `appcast.xml`, and publishes both files in a GitHub
Release. Sparkle reads the feed through GitHub's stable
`releases/latest/download/appcast.xml` URL.

See [docs/update-pipeline.md](docs/update-pipeline.md) for certificate setup,
release commands, key recovery, and first-release testing.
