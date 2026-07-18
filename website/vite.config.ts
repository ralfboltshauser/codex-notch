import { readFileSync } from "node:fs";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

interface ChangelogRelease {
  version: string;
  date: string;
  title: string;
  changes: string[];
}

const repository = "https://github.com/ralfboltshauser/codex-notch";
const plist = readFileSync(
  new URL("../apps/macos/AppResources/Info.plist", import.meta.url),
  "utf8",
);
const changelog = JSON.parse(
  readFileSync(
    new URL(
      "../apps/macos/Sources/CodexNotchApp/Resources/Changelog.json",
      import.meta.url,
    ),
    "utf8",
  ),
) as { releases: ChangelogRelease[] };

function plistString(key: string) {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = plist.match(
    new RegExp(`<key>${escapedKey}</key>\\s*<string>([^<]+)</string>`),
  );
  if (!match) throw new Error(`Missing ${key} in the macOS Info.plist`);
  return match[1];
}

const version = plistString("CFBundleShortVersionString");
const build = plistString("CFBundleVersion");
const latestRelease = changelog.releases[0];
if (!latestRelease || latestRelease.version !== version) {
  throw new Error(
    `Landing-page release drift: plist is ${version}, latest changelog is ${latestRelease?.version ?? "missing"}`,
  );
}

const download = `${repository}/releases/download/v${version}/CodexNotch-${version}.zip`;
const release = `${repository}/releases/tag/v${version}`;
const releaseReplacements: Record<string, string> = {
  "{{CODEX_NOTCH_VERSION}}": version,
  "{{CODEX_NOTCH_BUILD}}": build,
  "{{CODEX_NOTCH_DOWNLOAD}}": download,
  "{{CODEX_NOTCH_RELEASE}}": release,
};

export default defineConfig({
  plugins: [
    react(),
    {
      name: "codex-notch-release-metadata",
      transformIndexHtml(html) {
        return Object.entries(releaseReplacements).reduce(
          (result, [token, value]) => result.replaceAll(token, value),
          html,
        );
      },
    },
  ],
  define: {
    __CODEX_NOTCH_VERSION__: JSON.stringify(version),
    __CODEX_NOTCH_BUILD__: JSON.stringify(build),
    __CODEX_NOTCH_RELEASE_TITLE__: JSON.stringify(latestRelease.title),
    __CODEX_NOTCH_RELEASE_DATE__: JSON.stringify(latestRelease.date),
    __CODEX_NOTCH_RELEASE_CHANGES__: JSON.stringify(latestRelease.changes),
  },
  build: {
    target: "es2022",
  },
});
