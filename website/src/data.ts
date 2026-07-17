export const RELEASE = {
  version: "0.5.0",
  macos: "macOS 13+",
  architecture: "Apple silicon",
  download:
    "https://github.com/ralfboltshauser/codex-notch/releases/download/v0.5.0/CodexNotch-0.5.0.zip",
  release:
    "https://github.com/ralfboltshauser/codex-notch/releases/tag/v0.5.0",
  repository: "https://github.com/ralfboltshauser/codex-notch",
} as const;

export const STORY_SCENES = [
  "delegate",
  "signal",
  "return",
  "machines",
  "usage",
  "trust",
  "personal",
] as const;

export type StoryScene = (typeof STORY_SCENES)[number];
export type PageScene = "hero" | StoryScene | "final";

export interface Chapter {
  id: StoryScene;
  number: string;
  eyebrow: string;
  title: string;
  body: string;
  note: string;
}

export const CHAPTERS: Chapter[] = [
  {
    id: "delegate",
    number: "01",
    eyebrow: "Delegate",
    title: "Start the work. Leave the window.",
    body:
      "Open the notch whenever you want a factual view of what Codex is doing. It is not a guess based on a process name or stale transcript.",
    note:
      "Running stays quiet. A task that begins waiting for you can ask for attention.",
  },
  {
    id: "signal",
    number: "02",
    eyebrow: "The useful interruption",
    title: "It tells you enough—or waits quietly.",
    body:
      "Notify opens one compact outcome without taking focus. Glance leaves a numbered signal. Quiet simply collects.",
    note: "One attention policy for opening, sound, and unread state.",
  },
  {
    id: "return",
    number: "03",
    eyebrow: "Return",
    title: "One click back to the exact thread.",
    body:
      "Hover to grow the compact signal into your current task list. Choose a row and Codex Notch hands you back to the validated Codex thread.",
    note: "Try the completed row in the notch above.",
  },
  {
    id: "machines",
    number: "04",
    eyebrow: "Across machines",
    title: "One calm view, wherever the work runs.",
    body:
      "Keep the Mac interface local. Let Ubuntu machines publish completions and live state over the private Tailscale network you already control.",
    note: "No Codex Notch account. No hosted relay. No public port.",
  },
  {
    id: "usage",
    number: "05",
    eyebrow: "Account limits",
    title: "The windows Codex actually gives you.",
    body:
      "See primary and secondary windows labeled by their real duration. Seven-day history still owns the restrained local forecast.",
    note: "Whole percentages in, whole percentages out. No invented windows.",
  },
  {
    id: "trust",
    number: "06",
    eyebrow: "Private by architecture",
    title: "The signal, not your work.",
    body:
      "Codex Notch keeps only what it needs to show a task and bring you back. Your work stays where it belongs.",
    note:
      "No prompts or transcripts. Local outcome lines stay on the Mac; Ubuntu never sends model output or Codex credentials.",
  },
  {
    id: "personal",
    number: "07",
    eyebrow: "Native, quiet, yours",
    title: "A small surface with a point of view.",
    body:
      "Preview authored palettes on the real open notch, choose a completion tone, hide active tasks, or pick Notify, Glance, or Quiet without changing macOS Focus.",
    note: "Hover a palette below to preview it live.",
  },
];

export interface NotchTheme {
  id: string;
  name: string;
  mood: string;
  accent: string;
  secondary: string;
  top: string;
  bottom: string;
}

export const THEMES: NotchTheme[] = [
  {
    id: "obsidian",
    name: "Obsidian",
    mood: "Quiet · focused",
    accent: "#68e8b7",
    secondary: "#a6ffd7",
    top: "#020504",
    bottom: "#07130f",
  },
  {
    id: "aurora",
    name: "Aurora",
    mood: "Luminous · calm",
    accent: "#78e7ff",
    secondary: "#948bff",
    top: "#03060d",
    bottom: "#09152a",
  },
  {
    id: "ember",
    name: "Ember",
    mood: "Warm · energetic",
    accent: "#ffaa70",
    secondary: "#ff7189",
    top: "#090403",
    bottom: "#24100b",
  },
  {
    id: "amethyst",
    name: "Amethyst",
    mood: "Dreamy · precise",
    accent: "#caa7ff",
    secondary: "#f284c9",
    top: "#07040b",
    bottom: "#1d0e28",
  },
  {
    id: "cobalt",
    name: "Cobalt",
    mood: "Crisp · electric",
    accent: "#70a7ff",
    secondary: "#68f0dc",
    top: "#02050b",
    bottom: "#08162b",
  },
  {
    id: "dune",
    name: "Dune",
    mood: "Soft · considered",
    accent: "#e7ca8b",
    secondary: "#f5a96e",
    top: "#070604",
    bottom: "#1b160d",
  },
];
