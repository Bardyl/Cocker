# Releasing

Cocker is distributed as a signed and notarized `.app`. Without notarization
macOS does not merely warn about the app — it refuses to open it, and the user
is told the app is *damaged*. So the release path is not optional decoration.

## One-time setup

### Signing certificate

A **Developer ID Application** certificate, created from Xcode → Settings →
Accounts → *Manage Certificates…* → **+**. An "Apple Development" certificate is
not enough: it cannot be notarized.

Export it **with its private key** from Keychain Access as a `.p12`, then:

```sh
base64 -i Cocker.p12 | pbcopy      # goes into MACOS_CERTIFICATE
```

### Notarization credentials

An App Store Connect API key, from App Store Connect → Users and Access →
Integrations → *App Store Connect API* → Team Keys. Download the `.p8` — it is
offered **once** and cannot be downloaded again.

```sh
base64 -i AuthKey_XXXXXXXX.p8 | pbcopy   # goes into ASC_KEY_P8
```

### Repository secrets

| Secret | What it holds |
|---|---|
| `MACOS_CERTIFICATE` | The `.p12`, base64 encoded |
| `MACOS_CERTIFICATE_PASSWORD` | The password set when exporting it |
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: NAME (TEAMID)`, exactly as `security find-identity -v -p codesigning` prints it |
| `ASC_KEY_ID` | Key ID from App Store Connect |
| `ASC_ISSUER_ID` | Issuer ID from the same page |
| `ASC_KEY_P8` | The `.p8`, base64 encoded |

## Cutting a release

Release notes come from the tag annotation, so the tag must be annotated and
its message is what readers see:

```sh
git tag -a v0.1.0 -F - <<'NOTES'
Short line on what this release is about.

### What changed
- written for someone using the app, not reading the diff
NOTES

git push origin v0.1.0
```

GitHub can generate a commit list instead, but a commit list is not release
notes: it tells you what moved, never what changed for the person downloading
the app.

The `Release` workflow stamps the version into `Info.plist` from the tag, runs
the tests, signs with a hardened runtime, submits to Apple, waits for the
verdict, staples the ticket into the bundle and attaches the zip to a GitHub
release.

The version lives in the tag and nowhere else. `Info.plist` carries `0.1.0` for
local builds and is overwritten during the release.

## Checking a build by hand

```sh
codesign -dvvv build/Cocker.app          # authority, timestamp, runtime flag
codesign --verify --strict build/Cocker.app
spctl -a -vvv -t exec build/Cocker.app   # what Gatekeeper will decide
```

Before notarization `spctl` reports `rejected — Unnotarized Developer ID`. That
is expected, and it is exactly what a user downloading the app would hit.

## Local builds

`Scripts/bundle.sh` signs with a Developer ID when it finds one in the keychain,
and falls back to an ad-hoc signature otherwise — so contributors without an
Apple account can still build and run the app.

Set `COCKER_ADHOC=1` to force the ad-hoc path. Useful offline: the real
signature needs a timestamp from Apple's server.
