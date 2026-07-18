# Update pipeline

Codex Notch uses Sparkle 2.9.4 and GitHub Releases. A release contains:

- `CodexNotch-VERSION.zip`, with the signed, notarized, and stapled app
- `appcast.xml`, with signed feed metadata and the archive's Ed25519 signature

Every release also adds a newest-first entry to
`apps/macos/Sources/CodexNotchApp/Resources/Changelog.json`. That entry is
bundled into the Settings changelog and rendered verbatim as the GitHub Release
notes.

The stable feed URL is:

```text
https://github.com/ralfboltshauser/codex-notch/releases/latest/download/appcast.xml
```

## One-time Apple setup

Export the **Developer ID Application** identity and private key from Keychain
Access as a password-protected `.p12`, then configure the repository:

```sh
base64 < developer-id-application.p12 | tr -d '\n' \
  | gh secret set MACOS_CERTIFICATE_P12
printf '%s' 'P12_PASSWORD' | gh secret set MACOS_CERTIFICATE_PASSWORD
printf '%s' 'APPLE_ID_EMAIL' | gh secret set APPLE_ID
printf '%s' 'APPLE_TEAM_ID' | gh secret set APPLE_TEAM_ID
printf '%s' 'APP_SPECIFIC_PASSWORD' | gh secret set APPLE_APP_PASSWORD
```

Create the app-specific password at Apple Account sign-in and ensure the
Developer ID certificate belongs to `APPLE_TEAM_ID`.

The Sparkle key is already configured as `SPARKLE_PRIVATE_KEY`. Its seed must
remain identical to the `SUPublicEDKey` in
`apps/macos/AppResources/Info.plist`. The local
recovery copy is:

```text
~/.config/codex-notch/sparkle_private_key
```

Store another encrypted copy outside this machine. Never commit the seed.

## Publish

Before opening the release PR, write the new changelog entry and prepare the
matching version:

```sh
edit apps/macos/Sources/CodexNotchApp/Resources/Changelog.json
./scripts/prepare-release.sh 0.4.14
python3 scripts/changelog.py markdown 0.4.14
git add apps/macos/AppResources/Info.plist \
  apps/macos/Sources/CodexNotchApp/Resources/Changelog.json
git commit -m 'Prepare 0.4.14 release'
```

`python3 scripts/changelog.py validate` rejects missing, duplicate, malformed, or
out-of-order entries and requires the newest changelog version to match the app
version. CI and the tag workflow both run this validation.

After the release PR and the exact merged commit both pass CI, tag that verified
merge commit and push the tag to publish it.

The workflow rejects malformed versions, mismatches between the tag and
`CFBundleShortVersionString`, and tags that do not point to a commit on `main`.
It imports the certificate into an ephemeral keychain, signs inner Sparkle
helpers before the framework and app, notarizes the archive, generates the
signed appcast, and publishes a GitHub Release.

## Publish the product site

The signed-release workflow does not deploy `https://codex-notch.openexp.dev/`.
Deploy the site only after the matching GitHub Release and versioned archive are
available, so its primary CTA never points at an unpublished asset.

The Vercel project link in `website/.vercel/` is machine-local and ignored by
Git. Link it once when needed:

```sh
cd website
vercel link --project codex-notch
```

For each release, pull the production project settings, create the local Vercel
build output from the same checked-out release commit, and promote that exact
prebuilt output:

```sh
cd website
vercel pull --yes --environment production
vercel build --prod --yes
vercel deploy --prebuilt --prod --yes
```

`website/vercel.json` fixes the install command, Vite build, `dist` output, and
security headers. After promotion, verify the public alias rather than trusting
the deployment command alone:

```sh
curl -fsS https://codex-notch.openexp.dev/ | grep '"softwareVersion": "VERSION"'
curl -fsSI https://codex-notch.openexp.dev/ | grep -i '^x-vercel-id:'
curl -fsSIL "https://github.com/ralfboltshauser/codex-notch/releases/download/vVERSION/CodexNotch-VERSION.zip"
```

## First release

Version `0.3.0` is the first updater-capable build. Its feed returns `404` until
the `v0.3.0` release exists; Sparkle treats that as a failed probe and the app
continues normally. Install `0.3.0`, then publish a higher version to exercise
the complete update flow.
