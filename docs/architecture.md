# Architecture

Codex Notch is a small monorepo with two shipped applications and shared
repository tooling:

- `apps/macos` contains the Swift package for the menu-bar app and Stop-hook
  helper.
- `apps/linux` contains the Ubuntu publisher and live-state companion.
- `scripts` owns repository validation, packaging, and release support.

## macOS boundaries

`AppDelegate` is the composition root. It wires stores, listeners, monitors,
the settings window, and the overlay together. It should coordinate services;
it should not grow new rendering logic.

The notch UI has three layers:

1. `OverlayController` owns presentation state, task ordering, timers, shortcut
   freezing, and handoff actions.
2. `OverlayContentBuilder` maps an immutable configuration plus explicit
   actions into a view tree and returns typed references the controller updates.
3. Focused views (`ActiveTaskRowView`, `CompletedTaskRowView`, header views,
   primitives, and `OverlayContentView`) own drawing and interaction details.

Settings follow the same split. `OnboardingWindowController` owns navigation,
onboarding state, pairing operations, and transitions. Each settings tab is a
dedicated page view. `SettingsViewFactory` is the single source for common
labels, buttons, footers, grids, and page installation.

Keep domain state and wire formats outside AppKit views. `CodexNotchCore`
contains cross-process protocol types; app-side stores and monitors turn those
types into presentation state.

## Tests

macOS tests are grouped by behavior rather than by implementation file:

- usage parsing/history/forecasting;
- hook and task models;
- remote pairing, health, and listener behavior;
- overlay presentation and interaction;
- settings;
- uninstall behavior.

Shared fixtures and socket helpers live in `CodexNotchTestCase`. A behavior
change belongs in the narrowest suite that observes the user-facing contract.

`scripts/check_swift_structure.py` prevents a production Swift file from
exceeding 900 lines and a test file from exceeding 650 lines. Those limits are
not a substitute for design review; they are a tripwire that forces a component
boundary discussion before a controller or catch-all test file becomes a
monolith again.

## Verification

`make check-linux` is the portable preflight. It tests the Ubuntu companions and
repository tooling, validates the changelog, compiles Python, checks shell
syntax, and enforces the Swift structure limits. Ubuntu Swift parsing is an
additional syntax signal. macOS CI remains authoritative for AppKit type
checking, Swift tests, linking, and the packaged application build.
