# Codex Notch

A native, focus-safe macOS companion that turns the MacBook notch into a queue
for completed Codex tasks.

When a Codex turn finishes, a pitch-black HUD flows directly out of the MacBook
notch. It shows up to nine task titles, never becomes the key or main window,
and disappears after five seconds. Tasks remain queued until opened or
dismissed.

## Shortcuts

| Shortcut | Action |
|---|---|
| `Control-Shift-0` | Toggle the queue; stays open until toggled closed |
| `Control-Shift-1…9` | Open that task and remove it |
| `Option-Shift-1…9` | Dismiss that task |

Rows can also be clicked. Hovering reveals per-task dismiss buttons, Clear,
and connection settings.

## One-URL onboarding

The user provides one ntfy topic URL. The app then:

1. Validates the URL and checks topic access.
2. Saves it locally under `~/Library/Application Support/Ntfy Codex Overlay/`.
3. Safely merges a `Stop` hook into `~/.codex/hooks.json`.
4. Starts listening to the topic.
5. Guides the user through Codex's required hook trust review in `/hooks`.

The hook is the same native executable invoked with `--codex-hook`; there is no
Python runtime or loose hook script. Existing hook events and handlers are
preserved, and the previous `hooks.json` is backed up as `hooks.json.bak` before
changes.

The hook publishes only:

- the Codex task title;
- `Task finished` as a constant body;
- a validated `codex://threads/<UUID>` deep link.

It does not publish prompts, response text, transcripts, source code, or the
working-directory path.

## Install

Interactive onboarding:

```sh
./install-native-macos.sh
```

Preconfigure a topic while still showing the final trust step:

```sh
./install-native-macos.sh 'https://ntfy.example.com/my-codex-topic'
```

The installer builds an optimized arm64 binary, creates and ad-hoc signs
`~/Applications/Ntfy Codex Overlay.app`, and installs a user LaunchAgent. It
also removes the original Python listener LaunchAgent to prevent duplicate
opens.

## Security boundaries

- HTTPS is required, except HTTP for localhost development.
- Subscription URLs preserve ntfy auth query parameters.
- Incoming links must exactly match `codex://threads/new` or a UUID-shaped
  `codex://threads/<id>` URL. Query strings and other schemes are rejected.
- The overlay never becomes key or main; only an explicit task open activates
  Codex.
- The hook exits successfully even when ntfy is unavailable, so notification
  failures never block a Codex turn.
- Codex itself controls hook trust. The app does not bypass that safety check.

## Development

```sh
swift test
swift build -c release
```

The XCTest suite covers real ntfy event parsing, deep-link rejection, queue
semantics, topic normalization, authenticated subscription URLs, exact HUD
dimensions, hook payload privacy, and non-destructive/idempotent hook merging.

## Remove

```sh
./uninstall-native-macos.sh
```

Uninstalling removes the app, LaunchAgent, and only the hook handler installed
by this app. Other Codex hooks are preserved. App data remains in Application
Support so reinstalling can recover the connection.
