# Vibe Island learnings and Codex Notch decisions

Status: decision record, audited 2026-07-18

This document asks what Codex Notch should learn from the public Vibe Island
product and website without assuming that a visible feature is useful, reliable,
or better tested. Vibe Island is a useful comparison because it addresses a
similar top-of-screen workflow. It is not a specification for Codex Notch.

The decision standard is first-principles fit:

1. Does the capability help a person leave Codex without losing important
   state?
2. Does it reduce interruption, uncertainty, or the cost of returning?
3. Can the state be obtained faithfully from a documented source?
4. Can failure be made visible and recoverable?
5. Does it preserve Codex Notch's local, narrow security boundary?

If a feature fails one of those tests, competitor presence is not a reason to
build it.

## Bottom line

Take Vibe Island's **attention workflow and landing-page causal structure**, not
its breadth. Codex Notch should remain a peripheral Codex instrument: monitor
real state, surface consequences, and return to the exact task. It should not
become a second agent client, approval authority, terminal compatibility layer,
or orchestration surface.

The public Vibe Island pages provide evidence of careful iteration, including a
product demonstration near the promise, dedicated objection handling, a rich
changelog, repeated calls to action, and deployed event instrumentation. They
do **not** provide public conversion results, experiment design, reliability
rates, or evidence that their page converts better than ours. The correct claim
is therefore “useful patterns worth testing,” not “proven winning design.”

## Evidence ledger

### Directly observed

These facts were observed in the deployed public pages on 2026-07-18. They may
change after that date.

| Observation | Evidence | Confidence and limit |
| --- | --- | --- |
| The homepage moves from a concise promise to an immediate product scene, four outcome-oriented summaries, feature explanations, FAQ, and a repeated CTA. | [Vibe Island homepage](https://vibeisland.app/) and rendered desktop/mobile captures | High for page structure; no conversion effect is disclosed. |
| The site gives release recency its own detailed surface. | [Vibe Island changelog](https://vibeisland.app/changelog/) | High for presence and detail; update quality was not independently verified. |
| It publishes comparison and remote-work pages that answer high-intent questions outside the homepage. | [Alternatives](https://vibeisland.app/alternatives/) and [SSH remote](https://vibeisland.app/ssh-remote/) | High for information architecture; claims on vendor-authored pages remain marketing claims. |
| The deployed homepage source initializes PostHog, registers a site variant, and captures page, section, download, and purchase-related events. | [Deployed homepage source](https://vibeisland.app/) | High that instrumentation exists; low on whether it powered controlled experiments or better decisions. |
| The privacy policy names Sentry for crash reporting and PostHog for website analytics. | [Vibe Island privacy policy](https://vibeisland.app/privacy/) | High for the disclosed services; their configuration and retention were not audited. |
| The homepage says session content, tool names, and terminal metadata do not leave the machine while the website itself uses analytics. | [Homepage FAQ](https://vibeisland.app/) and [privacy policy](https://vibeisland.app/privacy/) | High for the words shown. The “no data” promise appears scoped to product/session data, but that scope can be misread. |
| The mobile CTA uses a handoff sheet rather than treating an iPhone as though it can install a Mac app. | Rendered mobile homepage behavior | High for behavior on the audited page; unknown whether it improves completion. |
| The main animated headline changes over time and several showcase effects autoplay. | Rendered homepage behavior | High for behavior; accessibility impact depends on implementation and user settings. |

### Inference, not fact

| Inference | Basis | Confidence |
| --- | --- | --- |
| Vibe Island's website has likely been iterated using behavioral data. | Variant labels and explicit CTA/section event capture exist in deployed source. | Medium. Instrumentation proves collection, not disciplined experiments. |
| Product evidence near the promise probably reduces comprehension cost. | A visitor can connect the claimed outcome to a visible mechanism without scrolling through abstract prose. | Medium-high as a usability hypothesis; unmeasured for Codex Notch. |
| FAQ and changelog likely reduce perceived purchase/install risk. | They answer compatibility, privacy, setup, and recency questions near the decision. | Medium; causal effect is unknown. |
| Provider breadth and GUI approvals create a larger compatibility and safety surface. | Each provider, terminal, hook, and approval transport adds independent lifecycle and failure states. | High as an engineering consequence; the competitor's actual defect rate is unknown. |
| A mobile handoff is more honest than a dead-end DMG link. | The current device cannot complete the Mac install, so share/copy/release actions match available capabilities. | High as a mapping and constraint argument; conversion impact is unknown. |

### Evidence we do not have

- No public A/B methodology, sample sizes, confidence intervals, or conversion
  results were found.
- No independent reliability, latency, crash, retention, or install-completion
  data were found.
- Public issue reports show possible failure classes, not current incidence or
  root cause. A report may be version-specific, misdiagnosed, or already fixed.
- A rendered marketing scene proves what the product communicates, not what the
  product does under reconnect, parallel-task, or failure conditions.

## First-principles product model

The user is not trying to “manage agents in a notch.” The underlying job is:

> Start Codex work, move attention elsewhere, notice only consequential state,
> then return to the exact work with enough context to decide what to do.

That job has four moments:

1. **Monitor:** establish what is still running from authoritative state.
2. **Signal:** distinguish routine progress from completion or a need for the
   user.
3. **Understand:** show the smallest useful context—project, branch, root task,
   collaborators, and bounded outcome.
4. **Return:** hand off to the exact Codex task when more context or action is
   needed.

The unit of attention is therefore a **consequence on a root task**, not an
agent, process, transcript line, terminal tab, or provider. That conceptual
model explains several scope decisions:

- Child agents roll into their root task instead of multiplying cards.
- A completion outcome is more valuable than a stream of tool activity.
- Approval state may be signalled, but the notch does not become the approval
  authority until a non-intercepting transport exists.
- The exact Codex task remains the full work surface and the recovery path.
- Remote support carries bounded state and outcomes; it does not become remote
  command execution.

The costs to minimize are also explicit:

| Cost | Product response |
| --- | --- |
| Interruption | Notify, Glance, and Quiet have distinct, visible consequences. |
| Missed consequence | Durable completion delivery, unread state, and visible connection/freshness status. |
| False confidence | Preserve last-known values with age instead of silently showing them as current or making them disappear. |
| Resumption effort | Project, branch, root task, outcome, and exact-thread handoff. |
| Security expansion | No remote approvals, remote commands, transcript upload, or provider-wide credential layer. |
| Cognitive overload | Bounded rows, root-task roll-up, no reasoning/tool stream, no orchestration canvas. |

## What to borrow from Vibe Island

Borrow the mechanism only when it serves the model above.

| Pattern | Codex Notch adaptation | Why it fits |
| --- | --- | --- |
| Product proof immediately after the promise | Show a faithful Mac/notch state in the first fold: real usage windows, a root task, child count, needs-input state, and a bounded completion outcome. | Connects promise to mechanism before asking for trust. |
| Outcome-oriented feature labels | Explain Monitor, Signal, Return, and Remote before listing implementation details. | Mirrors the user's workflow rather than repository architecture. |
| Rich changelog | Surface the latest signed release and link to the complete release history. | Recency and specificity are trust evidence for installable software. |
| FAQ near the final action | Answer hardware, OS, approvals, privacy, Tailscale, install, update, and removal questions. | Removes predictable uncertainty at the decision point. |
| Repeated CTA | Offer the same truthful download action after promise, evidence, and objections. | The action is available when the user becomes ready. |
| Mobile download handoff | On narrow/mobile devices, offer share, copy, release details, and an explicit “download anyway.” | Maps the action to what that device can actually do without trapping power users. |
| Dedicated high-intent documentation | Keep remote setup, release notes, architecture, privacy boundaries, and alternatives to over-broad features linkable. | Lets the homepage stay concise without hiding important constraints. |
| Demonstrated product states | Prefer faithful code-native states or real captures over decorative abstractions; label conceptual imagery. | Evidence earns trust only when its status is clear. |

Do not copy animated headline scrambling, autoplay for frequently revisited
content, `transition: all`, mutable accessible names, unsupported “zero data”
absolutes, or visual styling that dilutes Codex Notch's existing identity. Motion
must explain topology or feedback, stop under Reduce Motion, and never delay a
frequent action.

## Capability decision matrix

The matrix separates what 0.5.1 actually ships or retains from work that still
meets the product model but has not earned a shipped claim. An acceptance
condition describes “done”; a planned row must not be presented as current
behavior until that condition is met.

### Shipped or retained in 0.5.1

| Capability | First-principles reason | Acceptance condition |
| --- | --- | --- |
| Loaded-thread reconciliation | A connected client can still miss an active task if it relies on one list projection. | Reconcile documented loaded/list state with bounded metadata-only reads, cache only confirmed method-unavailable fallback, and fail closed on timeout, malformed data, incomplete enumeration, or transport failure. |
| Honest usage freshness | Disappearing a previously valid limit on one failed refresh destroys useful knowledge; presenting it as current creates false confidence. | Retain last-known windows, visibly distinguish stale from fresh, expose age, and recover automatically. |
| No network work in the remote Stop hook | Codex completion must not wait for network reachability. | Atomically enqueue first, return promptly, trigger an asynchronous flusher, and delete only after authenticated acknowledgement. |
| Bounded retry, deduplication, and backpressure | Durable delivery without bounds becomes disk growth or repeated interruption. | Stable event IDs, crash-durable atomic writes, bounded retry cadence, dedupe, strict acknowledgement retention, an exact 500-event ceiling, and age-based expiry. |
| Root-task collaboration roll-up | Multiple agents serving one outcome should not create multiple mental objects. | Child activity and needs-attention state elevate the root while child count/role remains inspectable. |
| Consequence-based attention policy | The same event must not open, sound, and count inconsistently. | Notify, Glance, and Quiet map to one tested disposition for each event class; the current mode and unread result remain visible. |
| Exact-thread handoff | A wrong return target is worse than no shortcut. | Accept only validated thread UUIDs, construct the URL locally, handle failure visibly, and never accept a remote URL or command. |
| Product-first landing page | Visitors need to see what the promise means before navigating a long narrative. | Faithful product proof appears in the desktop first fold, follows the hero quickly on mobile, and remains legible without animation. |
| Outcome/fact/objection landing sequence | Feature lists do not answer “is this for me, can I trust it, and what happens next?” | Monitor/Signal/Return/Remote proof, mechanism cards, latest release, FAQ, and repeated CTA use one consistent claim set. |
| Truthful mobile handoff | A mobile visitor cannot normally install a macOS app on the current device. | Native accessible dialog, share/copy fallback, release link, explicit download override, Escape/backdrop close, and restored focus. |
| One release truth source | Duplicated version/download copy silently drifts. | Website metadata and latest-release copy derive from signed app resources/changelog and fail the build on mismatch. |
| Website build gate | A polished page that can silently stop compiling or bundling is not trustworthy. | Typecheck and the production Vite build run in CI, with release metadata drift failing the build. |

### Next planned reliability work

| Capability | Why it still fits | Acceptance condition before claiming it |
| --- | --- | --- |
| Queue and transport diagnostics | A durable queue is recoverable but its exact backlog is not yet visible from Codex Notch. | Show bounded queue count, oldest age, last delivery result, and retry state in the remote CLI and Connections without prompts, outcomes, paths, tokens, host addresses, or free-form payloads. |
| Broader lifecycle compatibility fixtures | A happy-path snapshot does not establish behavior across every startup and reconnect order. | Automate launch-before-Codex, Codex-before-launch, reconnect, app-server restart, loaded task, multiple roots/children, stale usage, malformed payload, duplicate event, offline remote, retry, and shutdown. |
| Repeatable browser smoke gates | The 0.5.1 browser matrix was audited manually and is not yet a CI regression suite. | Automate keyboard, reduced-motion, 320/375/768/1024/1440 layout, contrast, link, structured-data, mobile-handoff, and no-JavaScript checks against a production build. |
| Redacted recovery diagnostics | Failure should explain the safe next step without exposing work. | Surface freshness, reconnect, and handoff failure using fixed enums and bounded labels; omit prompts, responses, full paths, tokens, origins, and arbitrary server text. |

### Prototype behind an explicit flag or research build

| Capability | Question to answer before shipping | Minimum prototype boundary |
| --- | --- | --- |
| Waiting reminder | Does a user-chosen reminder recover missed input without becoming another notification timer? | Off by default, visible deadline, one task-scoped reminder, cancel/snooze, no repeated nag loop. |
| Hover versus click activation | Can discovery improve without accidental openings near the camera/notch? | Compare edge hover delay, click target, and shortcut on real notch/no-notch screens; record accidental activation qualitatively. |
| Scheduled Quiet | Can a predictable schedule make silence legible without secretly reading or changing macOS Focus? | User-created local schedule, persistent mode signifier, temporary override, and clear next transition. |
| Child-attention disclosure | How much child identity helps before root-task clarity collapses? | Root remains primary; expose count and only the child that changes the decision. |
| Auxiliary-task suppression | Can setup/indexing/helper tasks be hidden without concealing work that needs the user? | Suppress only when stable typed metadata exists; never infer from title text; always elevate a consequence. |
| Context visibility | Which project/branch/role labels reduce wrong-task selection on minimum-width hardware? | Test bounded, redacted labels at actual compact widths; no full paths or origins. |
| Per-project attention policy | Do users need a small exception to the global mode, or does it create invisible mode errors? | At most one clearly signified override; no rules engine. |

### Defer until a dependency or evidence threshold is met

| Capability | Why deferred | Revisit when |
| --- | --- | --- |
| Actionable local approvals | Current hook/app-server paths can intercept or mutate Codex's native review lifecycle. | A documented, non-mutating subscription/response path preserves native and Auto Review behavior under disappearance, parallel requests, expiry, and another-client resolution. |
| Automatic Focus/recording/presentation scenes | Hidden automation makes silence hard to explain and platform detection may be incomplete. | macOS offers reliable state, mode feedback is designed, and every transition has an explicit override. |
| Multi-monitor duplicate overlays | Duplicated signals may increase confusion and geometry failure states. | Real use shows the active-screen model is insufficient and ownership/movement rules are defined. |
| Large shortcut matrices | More shortcuts add collision, recall, and settings cost. | Repeated use demonstrates a high-frequency action not served by open and handoff shortcuts. |
| Additional usage forecasts | A projection without enough history or a faithful window model looks authoritative while being speculative. | The upstream window is stable and a conservative forecast can expose assumptions and error. |

### Reject for Codex Notch

| Capability | Reason |
| --- | --- |
| Remote approval or command execution | Cross-host authorization changes the threat model and exceeds a peripheral signal instrument. |
| Raw reasoning, transcript, or tool-event feed | High noise and privacy cost; recreates the Codex work surface in the notch. |
| Multi-provider aggregation | Provider/terminal breadth is a different product whose compatibility cost weakens Codex-specific correctness. |
| Agent orchestration or task creation | The notch should reveal consequence and return to Codex, not become a second control plane. |
| Terminal adapters and jump heuristics | Exact Codex task identity is safer and conceptually simpler than maintaining terminal-specific focus automation. |
| Direct network send in a completion hook | Network latency and reachability must never extend Codex's completion critical path. |
| Transcript parsing or another model call for outcomes | Both add latency and uncertainty when the Stop hook already supplies a bounded final message locally. |
| Hidden title/path heuristics as authority | User-generated text is unstable metadata; it must not decide suppression, privilege, or routing. |
| Custom sound-pack infrastructure | It expands configuration and asset maintenance without improving state comprehension. Curated bounded feedback is enough. |
| Managed SSH or a general remote shell | Existing user-controlled SSH over a private tailnet is transport, not a product invitation to execute arbitrary commands. |
| Persistent grants or “always allow” | A compact peripheral surface cannot safely communicate the scope and future consequences of a durable grant. |

## *The Design of Everyday Things* translated into requirements

The design vocabulary is useful only when it creates testable behavior.

| Principle | Requirement in Codex Notch | Failure to avoid |
| --- | --- | --- |
| **Affordance** | A task row affords inspection/handoff only when it is actually actionable. The top edge, physical notch, and shortcut all provide a reachable way to open. | A decorative row that looks clickable but has no valid task, or a hover-only control on a no-notch display. |
| **Signifier** | Labels and shape identify Running, Needs input, Finished, stale usage, unread count, active attention mode, remote/offline, and CTA platform requirements. | Color-only status, a silent mode with no visible cause, or a “Download” action that hides Apple-silicon/macOS constraints. |
| **Natural mapping** | Notify opens completions with sound; Glance badges routine completions; a task newly needing the user opens in either mode; Quiet collects without opening. Product flow maps Monitor → Signal → Understand → Return. | Separate toggles whose combinations produce surprising sound/open/count behavior. |
| **Feedback** | Every consequential event has a visible disposition; enqueue acknowledges durable capture; handoff failure stays on screen; stale values show age; mode changes show the resulting behavior. | A hook blocks silently, a click appears to succeed but opens the wrong task, or old usage looks live. |
| **Constraints** | Bounded text, validated UUIDs, typed metadata, sanitized labels, atomic files, local URL construction, no remote verdicts, no persistent approval, and no quick-approve shortcut. | Making an unsafe action easy and trying to explain the risk afterward. |
| **Conceptual model** | One row is one root task. Child agents contribute to it. The notch carries signal; Codex owns full context and action. | A card stream that equates every child process with a separate user goal. |
| **Knowledge in the world** | Put project, branch, outcome, collaborator count, freshness, mode, and recovery action where they change a decision. | Requiring the user to remember what an unlabeled task or hidden mode means. |
| **Error prevention and forgiveness** | Prefer non-interception, idempotency, bounded retries, safe fallbacks, and exact-thread recovery. Keep the original Codex surface reachable. | A one-click destructive verdict or failure that consumes the only copy of an event. |

The motion corollary is frequency-sensitive: repeated counters, shortcut opens,
selection, and handoff respond immediately; an occasional completion may use a
short top-anchored transition to explain where the signal arrived. Reduce Motion
replaces spatial movement with an instant state change or brief opacity change.

## Reliability model and failure modes

Reliability is not “the connection usually works.” It is the ability to state
what is authoritative, what is last known, what is queued, and what the user can
do when any layer fails.

| Boundary | Failure mode | Observable feedback | Control and test |
| --- | --- | --- | --- |
| Codex state discovery | A task is loaded but absent from the projection being watched. | Connection may be healthy while the task count is suspiciously incomplete. | Reconcile documented loaded/list state with bounded reads; fixture launch order, reconnect, restart, and fallback. |
| Event lifecycle | Start/update/complete arrive out of order, duplicate, or after reconnect. | No phantom duplicate row; last transition and source remain inspectable in diagnostics. | Stable IDs, idempotent reducers, monotonic/explicit timestamps, replace-only snapshots, lifecycle permutations. |
| Usage polling | One refresh fails after a valid sample. | Last-known value remains with “stale” age and recovery indication. | Separate value from freshness; backoff; clock-boundary and malformed-response tests. |
| Local completion capture | Process exits or app is absent while the hook runs. | Completion remains in an atomic local inbox and appears after recovery. | Write temp + rename, bounded payload, corrupt-file quarantine, launch-after-event fixture. |
| Remote completion capture | Network is slow/offline at Stop time. | Hook completes locally and the paired host becomes visibly unreachable; the completion remains queued. Exact queue count/age is planned, not current. | Atomic outbox first, no socket in hook path, asynchronous service trigger, offline and timeout tests. |
| Remote replay | ACK is lost, service restarts, or duplicate delivery occurs. | One completion is shown, queue clears only after acknowledged receipt. | Event ID dedupe, authenticated ACK, replay after crash, bounded retries and retention. |
| Live remote state | Host disconnects while rows remain visible. | Rows are labelled last-known/offline or expire by a documented rule; they never appear live indefinitely. | Heartbeat/freshness clock, replace-only host snapshot, disconnect/reconnect tests. |
| Collaboration roll-up | A child needs input while its root still reports running. | Root elevates to Needs input and identifies the contributing child in expanded context. | Deterministic severity ordering and parent/child fixtures. |
| Attention policy | Sound, opening, and unread count diverge. | Selected mode and event disposition are visible and explainable. | One policy reducer with a table test for event × mode; no scattered preference checks. |
| Handoff | UUID is malformed, stale, or resolves to another task. | Stay in the notch, state that handoff failed, and offer a safe retry/open-Codex path. | Validate locally, construct fixed-scheme URL locally, never execute remote text, test malformed/stale IDs. |
| Approval signal | A compact UI intercepts native/automatic review or resolves a stale request. | Current product signals “Needs approval” and returns to Codex; it does not decide. | Keep actions disabled until the approval exit criteria in `docs/attention-workflow.md` are met. |
| Update/release | Website, bundle, appcast, and release page disagree. | Build fails before release rather than publishing contradictory metadata. | One authoritative version/changelog source and signed release pipeline checks. |
| Landing page | A visual or script fails, motion is disabled, or the viewport is narrow. | Promise, evidence, constraints, FAQ, and download path remain available. | Semantic HTML, progressive enhancement, reduced-motion path, keyboard/mobile captures, build/link smoke tests. |

### Community reports as warning evidence

The following public reports informed the failure taxonomy, not estimates of
quality. We have not reproduced them and do not know whether they affect the
current Vibe Island release:

- silent terminal-jump report: [community issue 166](https://github.com/vibeislandapp/community/issues/166)
- wrong-thread jump report: [updates issue 15](https://github.com/edwluo/vibe-island-updates/issues/15)

Four other issue URLs surfaced during the initial search for reconnect, hook
latency, approval interception, and hidden-filter symptoms, but returned 404 in
the final link check. They are intentionally omitted rather than treated as
reopenable evidence.

The lesson is not “Vibe Island is unreliable.” It is that reconnect, hook
latency, routing, approval interception, and hidden filtering are predictable
failure classes for this category and deserve explicit contracts before feature
breadth.

Codex App Server behavior is a moving compatibility dependency. Any state or
handoff implementation must be rechecked against the current
[official App Server documentation and schemas](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md),
not remembered from an older release.

## Landing-page causal structure

The page should answer questions in the order a new visitor actually encounters
them:

```text
Is this for me?
    ↓
What does it let me stop doing?
    ↓
Can I see the real mechanism?
    ↓
Why should I trust the state, privacy boundary, and release?
    ↓
Will it work on my setup, and what does it not do?
    ↓
What is the next reversible action?
```

Recommended sequence:

| Page layer | Visitor question | Required content | Anti-pattern |
| --- | --- | --- | --- |
| Header | Where am I and where can I go? | Brand, How it works, Why it works, FAQ, What's new, platform-specific CTA. | A large navigation taxonomy or claims not repeated on the page. |
| Hero | What outcome do I get? | “Leave the Codex window. Keep the signal.” with a concise Mac/Codex constraint and one primary CTA. | Cycling claims, provider-count boasting, or unexplained jargon. |
| First-fold product proof | What does that promise mean in the product? | Faithful compact/full notch state showing real windows, project/branch, root/children, Needs input, and completion outcome. | Generic glass hardware with no decision-making information. |
| Proof rail | What are the four moments? | Monitor, Signal, Return, Remote; one consequence-focused sentence each. | Repeating implementation names before explaining value. |
| How it works | What happens when I leave and return? | Delegate → receive useful signal → exact-thread handoff, with an interactive demo that does not gate comprehension. | Autoplay as the only way to learn or motion that restarts on every interaction. |
| Mechanism facts | Why is this trustworthy? | Authoritative state, consequence-based attention, local bounded outcome, validated return, private remote path, honest usage windows. | “Magic,” “zero config,” or privacy absolutes without boundaries. |
| Latest release | Is it alive and installable? | Version, build/date, concrete changes, signed/notarized status, full changelog/release link. | Fake social proof or manually duplicated version copy. |
| FAQ | Will it work for me and what is the risk? | Requirements, no-notch support, approval limits, data boundary, Tailscale, install/update/removal. | Hiding exclusions in docs after the download action. |
| Final CTA/footer | What should I do now? | Repeat the same download action and provide source, docs, privacy, release, FAQ. | Introducing a new promise or more aggressive action at the bottom. |

This is a causal argument, not a clone of Vibe Island's visual language:

```text
Outcome claim
  → faithful product evidence
  → mechanism and boundaries
  → current release proof
  → objection resolution
  → reversible download action
```

### Landing quality gates

- The H1 and its accessible name are stable.
- The first desktop viewport contains the outcome, platform constraint, CTA,
  and meaningful product evidence; mobile reaches evidence without passing a
  long decorative scene.
- Product visualizations use current product facts and are labelled if they are
  conceptual rather than screenshots.
- Every CTA has the same destination semantics and works without pointer hover.
- The mobile dialog traps focus natively, closes with Escape, restores focus,
  and keeps a direct-download override.
- FAQ uses native disclosure semantics and remains keyboard-operable.
- Focus-visible styles are obvious, status is not color-only, and text maintains
  contrast across supported themes.
- `prefers-reduced-motion` removes non-essential spatial and autoplay behavior;
  `prefers-reduced-transparency` remains legible.
- Responsive captures cover at least 320, 375, 768, 1024, and 1440 CSS pixels.
- Metadata, structured data, CTA version, latest-release copy, and app resources
  cannot disagree silently.
- The production build, links, headings, structured data, and no-JavaScript
  download path receive repeatable checks.

## Privacy-preserving measurement contract

No analytics provider should be added merely because Vibe Island uses one.
Measurement begins with a decision question and a data-minimization contract.
Until a collection path satisfies the contract below and the privacy notice is
updated, the website should ship with no behavioral analytics.

### Questions, not vanity metrics

| Question | Directional measure | Important limit |
| --- | --- | --- |
| Does early product proof help visitors act? | Primary CTA activations per landing view, split only by fixed page variant and CTA placement. | A click is not a download, install, launch, or retained user. |
| Does the demo clarify the mechanism? | Preview-to-demo activations and demo interactions per landing view. | Non-interaction may mean the static proof was already sufficient. |
| Which objections matter? | FAQ opens per stable question ID. | An open can signal interest, confusion, or simple curiosity; it is not automatically negative. |
| Does release evidence earn deeper trust? | Latest-release/release-history activations per landing view. | This measures investigation, not trust itself. |
| Does mobile handoff prevent a dead end? | Share, copy, release, and explicit download-anyway actions per mobile handoff open. | We cannot observe whether sharing later produced an install without cross-device identity, which we reject. |

Installation, successful first launch, task handoff, and retention are product
questions. Do not infer them from website clicks, and do not join website events
to local app activity. GitHub's aggregate release download counts may be reviewed
separately but must not be linked to a visitor.

### Allowed event vocabulary

Only explicit, enumerated events may be collected:

| Event | Allowed properties |
| --- | --- |
| `landing_view` | `site_version`, `page_variant`, `viewport_bucket` |
| `cta_activate` | `site_version`, `page_variant`, `placement` (`header`, `hero`, `release`, `final`), `action` (`download`, `release`) |
| `preview_demo_activate` | `site_version`, `page_variant` |
| `demo_interact` | `site_version`, `control_id` from a fixed enum |
| `section_reached` | `site_version`, `section_id` from a fixed enum |
| `faq_toggle` | `site_version`, `question_id` from a fixed enum, `state` (`open`, `closed`) |
| `mobile_handoff` | `site_version`, `action` (`open`, `share`, `copy`, `release`, `download_anyway`) |
| `release_open` | `site_version`, `placement` from a fixed enum |

`viewport_bucket` may be only `narrow`, `medium`, or `wide`. It must not contain
exact dimensions. Event properties may not contain user-supplied strings.

### Data that must never be collected

- distinct, anonymous, device, advertising, installation, or cross-session IDs
- cookies, local-storage identifiers, fingerprint components, or session replay
- prompts, responses, task titles, project names, branches, paths, thread IDs,
  hostnames, remote-host labels, IP addresses, or Codex usage data
- full URLs, query strings, UTM parameters, referrers, clipboard contents, share
  targets, or raw user-agent strings
- DOM autocapture, free-form error text, keystrokes, pointer traces, or form
  values
- joins between website activity, GitHub identity/downloads, app activity, crash
  reports, or support requests

If infrastructure receives an IP address at the transport layer, it must discard
it before event storage and disable access logs for the event endpoint. A
provider that cannot meet this requirement is ineligible.

### Processing and retention

- Count only `{UTC day, site version, page variant, event, allowed enums}`.
- Aggregate at ingestion; do not retain a user-level or request-level event log.
- Retain daily aggregates for at most 90 days, then delete them.
- Do not create user/session funnels. Ratios are aggregate numerator/denominator
  comparisons only.
- Suppress externally shared slices with fewer than 20 events.
- Honor Global Privacy Control and Do Not Track by sending no event.
- Keep the site fully functional when collection is blocked or unavailable.
- Publish the exact event dictionary and retention in the privacy documentation
  before enabling collection.

### Experiment discipline

The existence of a `page_variant` property does not make a change an experiment.
Before making a causal claim:

1. Write one hypothesis and one primary measure before rollout.
2. Change one meaningful variable at a time.
3. Choose the sample/time stopping rule before reading results.
4. Keep accessibility, page weight, runtime errors, and truthful copy as
   non-negotiable guardrails.
5. If variants are used, assign them randomly in memory per page load without a
   persistent identifier. Accept that this estimates page-view response, not
   user conversion.
6. Report uncertainty and time/channel confounders. A before/after comparison is
   directional evidence, not a randomized result.
7. Do not optimize a CTA click at the expense of compatibility disclosure,
   privacy, or the user's ability to make a reversible decision.

Until enough observations exist under a declared stopping rule, the landing
upgrade remains a reasoned design change with unmeasured conversion impact.

## Reassessment triggers

Reopen these decisions only when new foundational evidence changes the model:

- Codex exposes a documented, non-mutating approval or observation transport.
- App Server schemas change the available active/task/parent/freshness facts.
- Real users repeatedly fail to discover the top-edge or exact-thread handoff.
- Diagnostics show a material class of lost/duplicated/stale events after the
  lifecycle matrix passes.
- Privacy-preserving aggregate measurement shows a stable comprehension or CTA
  problem large enough to justify another page change.
- A requested provider/terminal capability represents a different user job
  important enough to justify a separate product, not scope creep here.

## Known uncertainty after this review

- We do not know whether Vibe Island's landing page converts better than the
  previous Codex Notch page.
- We do not know how rigorously Vibe Island uses its deployed instrumentation.
- We do not know the current prevalence or root causes of the cited community
  reports.
- We have not measured the redesigned Codex Notch page with real visitors.
- Ubuntu builds and browser captures cannot establish native AppKit behavior;
  macOS CI and real-device checks remain authoritative for the app.
- Codex App Server is versioned upstream behavior and must be revalidated rather
  than treated as a permanent abstraction.

Those are not reasons to copy more or to stop. They define what must be tested
next and prevent confidence from outrunning evidence.
