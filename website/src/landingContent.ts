export interface ProofPoint {
  label: string;
  value: string;
  target: string;
}

export const PROOF_POINTS: ProofPoint[] = [
  { label: "Monitor", value: "Live root-task state", target: "#delegate" },
  { label: "Signal", value: "Notify, Glance, or Quiet", target: "#signal" },
  { label: "Return", value: "The exact Codex thread", target: "#return" },
  { label: "Remote", value: "Private Mac + Ubuntu", target: "#machines" },
];

export interface FeatureFact {
  number: string;
  eyebrow: string;
  title: string;
  body: string;
  accent?: boolean;
}

export const FEATURE_FACTS: FeatureFact[] = [
  {
    number: "01",
    eyebrow: "Root-task clarity",
    title: "One task, even when several agents are helping.",
    body:
      "Project and branch distinguish similar work. Nested agents roll into the root task, and a child that needs you elevates that root.",
    accent: true,
  },
  {
    number: "02",
    eyebrow: "Attention by consequence",
    title: "Choose what the signal actually does.",
    body:
      "Notify opens completions and sounds. Glance badges completions, but a task that starts needing you opens in either mode. Quiet only collects.",
  },
  {
    number: "03",
    eyebrow: "Useful completion",
    title: "Know the outcome before switching context.",
    body:
      "A local completion can show one bounded line from Codex’s final response. It is deterministic, optional, and never sent by Ubuntu.",
  },
  {
    number: "04",
    eyebrow: "Exact return",
    title: "The row is a way back, not another workspace.",
    body:
      "Codex Notch validates the thread identity and constructs the Codex deep link itself. Remote payloads cannot supply a URL or command.",
  },
  {
    number: "05",
    eyebrow: "Private remote",
    title: "Your machines talk over the tailnet you control.",
    body:
      "Per-host authentication, durable delivery, acknowledgements, and replace-only live snapshots—without a Codex Notch cloud service or public listener.",
  },
  {
    number: "06",
    eyebrow: "Honest limits",
    title: "Show the windows Codex actually returns.",
    body:
      "Primary and secondary limits keep their real duration labels. Only an exact seven-day window enters local history and forecasting.",
  },
];

export interface LandingFAQ {
  question: string;
  answer: string;
}

export const LANDING_FAQS: LandingFAQ[] = [
  {
    question: "What do I need to run Codex Notch?",
    answer:
      "An Apple silicon Mac on macOS 13 or later, plus Codex CLI on every machine that runs Codex. Tailscale, key-based SSH, and Python 3 are needed only when you add an Ubuntu host.",
  },
  {
    question: "Does it need a MacBook with a physical notch?",
    answer:
      "No. On a notched display it extends from the hardware. On another display it uses the same top-center screen edge, and the global shortcut remains available.",
  },
  {
    question: "Does Codex Notch approve commands for me?",
    answer:
      "No. It can show that a task needs approval or input and take you to the exact Codex thread, but Codex remains the place that decides. The app does not intercept native review or silently weaken Auto Review.",
  },
  {
    question: "What leaves an Ubuntu machine?",
    answer:
      "Each envelope carries its random per-host pairing token for authentication. The task payload is limited to validated thread identity, a bounded title, source, state, timestamp, sanitized project/branch context, and optional agent labels. Full working directories; prompt, transcript, or model-output bodies; Codex account credentials; and remotely supplied navigation URL or command fields are not included.",
  },
  {
    question: "Why does remote monitoring use Tailscale?",
    answer:
      "It keeps the receiver on a private tailnet address instead of a public listener. Each Ubuntu host also receives its own random pairing token. Tailscale may use its DERP transport when a direct path is unavailable; Codex Notch adds no cloud relay of its own.",
  },
  {
    question: "How are installation, updates, and removal handled?",
    answer:
      "Release builds are Developer ID signed, notarized, and stapled. Sparkle verifies both Apple signing and an Ed25519 update signature. Settings can remove local hooks and retry cleanup on paired Ubuntu hosts before deleting the app’s local data.",
  },
];
