# Attention workflow

Codex Notch is a peripheral attention instrument, not a second Codex client.
Its job is to answer three questions with the least interruption possible:

1. What is still working?
2. What needs me?
3. What finished, and is the result worth opening?

This document records the product and protocol decisions behind the 0.5 line.
It is intentionally narrower than Vibe Island: Codex remains the authority,
the notch carries signal, and exact-thread handoff remains the escape route.

## Ground truth checked before implementation

- Active state comes from Codex App Server `thread/list`; it is replace-only
  and remains in memory.
- Codex `Stop` hook input includes `last_assistant_message`. A deterministic
  local excerpt can therefore improve a completion without transcript parsing
  or another model call.
- App Server thread records include `cwd`, `gitInfo.branch`,
  `parentThreadId`, `agentNickname`, and `agentRole`. Project and collaboration
  context can be projected without sending a full path or origin URL.
- Rate-limit snapshots contain independent primary and secondary windows with
  their own durations and reset times. An exact seven-day parser is not a
  faithful model of that payload.
- A `PermissionRequest` hook can return only allow or deny today. It executes
  before native and automatic review, so waiting on a Notch decision delays
  that existing path.
- App Server fans approval requests to clients subscribed to a thread, but it
  has no view-only subscribe operation. `thread/resume` subscribes and also
  replaces live client metadata and MCP elicitation behavior. Codex Notch will
  not use that as an undocumented shortcut.

The Codex facts above were checked against the locally installed Codex 0.144.4
schemas and current `openai/codex` source. They are compatibility dependencies,
not assumptions that should be silently carried forward.

## Decisions

| Capability | Decision | Reason |
| --- | --- | --- |
| One-line completion outcome | Build | High information value; deterministic and local. |
| Project and branch identity | Build | Makes similar titles recognizable without exposing full paths. |
| Parent-level subagent roll-up | Build | Preserves one root-task mental model while elevating child attention. |
| Notify / Glance / Quiet | Build | One policy must govern opening, sound, and unread state. |
| Actual usage windows | Build | Fixes a protocol-model mismatch with low behavioral risk. |
| Focus, lock, sharing, or schedule automation | Defer | Reliable detection and visible mode feedback need a separate design; hidden automatic modes would make silence hard to explain. |
| Local actionable approvals | Defer behind safety gates | Current transports either intercept native review or mutate a live App Server thread. |
| Remote approvals | Reject | Sending and authorizing commands across hosts breaks the current security boundary. |
| Raw reasoning/tool dashboard | Reject | Adds noise and turns the notch into another work surface. |
| More agent providers | Reject | Codex focus is a product advantage, not a missing integration list. |

## Attention policy

The user chooses one global mode. Event defaults remain deliberate so a low
priority update never behaves like a blocked task.

| Event | Notify | Glance | Quiet |
| --- | --- | --- | --- |
| Completion | Open compact result and play the selected sound | Add to the numbered notch badge | Collect only |
| Approval or input state | Open | Open | Collect only |
| Update or connection signal | Add to the numbered notch badge | Add to the numbered notch badge | Collect only |

Opening the notch clears the glance count. Mode changes do not pretend that
unseen work was seen. Repeated completions from one thread share one count, and
evicted rows leave the count, so every number maps to inspectable content.
Quiet temporarily hides an existing capsule; leaving Quiet restores its count.
Glance uses a numbered capsule that hangs from the notch edge; it does not use
a standalone green dot that could be mistaken for macOS camera or microphone
privacy state.

## Everyday-object design rules

The interface applies the core lessons of *The Design of Everyday Things* as
concrete constraints:

- **Conceptual model:** one row is one root task. Collaborating agents belong
  to it and elevate its status instead of becoming an unrelated card stream.
- **Knowledge in the world:** title, project, branch, outcome, agent count, and
  attention state are visible where they change the decision.
- **Natural mapping:** attention settings describe their observable result—
  open and sound, numbered badge, or collect only.
- **Feedback:** a completed event either opens, increments a visible count, or
  follows an explicitly selected Quiet mode. Sound never contradicts Quiet.
- **Constraints:** bounded text, sanitized path labels, no remote verdicts, no
  persistent grants, and no quick-approve keyboard shortcut.
- **Forgiveness:** exact-thread handoff remains available whenever the notch is
  not the right place to decide.
- **Mode visibility:** the numbered badge makes an unseen Glance state visible;
  Settings keeps all three modes side by side instead of hiding one behind a
  toggle label.

## Motion and interaction rules

- Live counters, status changes, and shortcut navigation do not animate.
- Keyboard-initiated open and task handoff remain immediate.
- The occasional completion opening may use the existing short, top-anchored
  transition because it explains where the signal came from.
- Glance appears with a short opacity fade only. Repeated count updates do not
  replay an entrance animation.
- Pressable controls respond on pointer-down with the existing restrained
  scale feedback.
- Reduce Motion replaces spatial movement with the existing short fade.

These rules follow the frequency test: repeated operations prioritize response;
occasional state arrival may use motion to explain topology.

## Data and privacy boundaries

- Completion outcomes are optional when supplied by the Stop hook, locally
  extracted, bounded, and stored with the local ten-item completion history.
  The setting controls whether that line is shown. Remote completion payloads
  omit it.
- Remote active snapshots may contain only a sanitized project basename,
  branch, and collaboration metadata. They never contain a full cwd or origin
  URL.
- Active tasks and child roll-ups remain replace-only and memory-only.
- Usage history retains only the seven-day projection needed for the existing
  forecast. Other windows are displayed but not forecast.

## Approval exit criteria

Actionable local approvals should ship only after one transport can meet all of
these conditions:

1. The app can disappear without delaying or losing Codex's native approval.
2. Auto Review behavior is detectable, preserved, and covered by a real
   compatibility test.
3. Parallel requests have unique identities, deterministic ordering, expiry,
   crash cleanup, and resolution-from-another-client handling.
4. Unknown or truncated tool inputs cannot expose an Allow action.
5. Only Allow once, Deny, and Review in Codex are offered.
6. The feature is local-only, opt-in, and explicitly states that it can decide
   before Codex's normal reviewer.

Until Codex exposes a non-mutating subscribe operation or richer hook context,
the correct behavior is to show “Needs approval” and hand off to Codex.

## Verification and release gates

- Pure projections and formatters require fixture tests on Swift and Python.
- Existing v1 completion and remote snapshots must continue decoding.
- Header layout must pass on a minimum-width hardware-notch geometry.
- Settings controls must remain non-overlapping inside the fixed 720×650
  window.
- Ubuntu preflight and Swift parsing are early signals only. macOS CI is
  authoritative for AppKit types, package tests, and the app bundle.
- The release must pass PR CI and exact merged-main CI before the verified
  merge commit is tagged.
