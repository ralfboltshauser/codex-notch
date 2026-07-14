# Update pipeline

Codex Notch uses Sparkle 2.9.4 and GitHub Releases. A release contains:

- `CodexNotch-VERSION.zip`, with the signed, notarized, and stapled app
- `appcast.xml`, with signed feed metadata and the archive's Ed25519 signature

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
remain identical to the `SUPublicEDKey` in `AppResources/Info.plist`. The local
recovery copy is:

```text
~/.config/codex-notch/sparkle_private_key
```

Store another encrypted copy outside this machine. Never commit the seed.

## Publish

After merging the intended release commit to `main`:

```sh
./prepare-release.sh 0.3.1
git add AppResources/Info.plist
git commit -m 'Prepare 0.3.1 release'
git push origin main
git tag v0.3.1
git push origin v0.3.1
```

The workflow rejects malformed versions, mismatches between the tag and
`CFBundleShortVersionString`, and tags that do not point to a commit on `main`.
It imports the certificate into an ephemeral keychain, signs inner Sparkle
helpers before the framework and app, notarizes the archive, generates the
signed appcast, and publishes a GitHub Release.

## First release

Version `0.3.0` is the first updater-capable build. Its feed returns `404` until
the `v0.3.0` release exists; Sparkle treats that as a failed probe and the app
continues normally. Install `0.3.0`, then publish a higher version to exercise
the complete update flow.
