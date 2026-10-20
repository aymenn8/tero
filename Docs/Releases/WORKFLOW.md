# Local automatic releases

Only Tero Dev and Tero Prod use the shared backend. Source changes remain on feature branches until accepted. A release is an immutable committed source snapshot; ignored local credentials and unrelated untracked files are excluded.

`make publish` automatically chooses the initial version (0.0.1) or increments the last public patch version, increments the build counter, archives a universal signed Production app, creates a DMG with an Applications shortcut, submits the signed DMG to Apple once, waits, staples and validates the ticket, uploads assets to a draft, and publishes the complete GitHub Release as Latest. No manual draft publication is required. An explicit version is optional: `make publish VERSION=0.1.0`.

Configuration is in `Configuration/release.json`; it contains no secrets. GitHub credentials and the Developer ID private key remain in Keychain. Distribution requires the `tero-notary` Keychain credential profile. One-time setup in an interactive local terminal:

```
xcrun notarytool store-credentials tero-notary --team-id 52WH9VZ63T
```

Use the Apple Developer account and an app-specific password from account.apple.com. Never paste the password into chat, config, shell command arguments or Git. The tool prompts securely and validates the credentials before saving them. `make release-check` verifies access without building, creating a repository or publishing.

The script creates `aymenn8/tero-releases` as a public assets-only repository when the first release begins. Source code is never pushed there. Artifacts: `Tero.dmg`, signed `appcast.xml`, `SHA256SUMS.txt`, and `release.json` (version, build, source commit, digest and exact download URL). GitHub notes are the changelog. If `Docs/Releases/<version>.md` exists in the pinned source, it is used; otherwise committed subjects since the previous release generate notes automatically.

A dedicated local `~/Library/Application Support/Tero Releases/` workspace stores status, snapshots, logs and artifacts outside the cloud-managed source folder and outside Git. Re-run the same command to resume an interrupted upload or Apple wait. A file lock prevents concurrent local publishes; hashes prevent approval reuse on changed artifacts. Published versions cannot be overwritten. Failed builds, Apple rejection and failed uploads stop before publication. A repeated command on the already published commit is a no-op. Keep the Mac awake/available until publication, or resume after it wakes.

A notarization request runs on Apple's infrastructure. Waiting on the local Mac consumes no hosted GitHub Actions minutes. The optional manual Actions workflow calls the same script on a trusted self-hosted owner Mac; it is not installed automatically and is never triggered by public pull requests. `make publish` does not need that runner.

Website discovery uses the public releases repository: the Download page enables only when a published Latest release includes Tero.dmg, and public release notes feed the Changelog page. A short server cache means updates may take a few minutes to appear. No Vercel variable edit is needed for each version. An explicit TERO_DOWNLOAD_URL still overrides GitHub discovery when configured.

Sparkle 2.10.0 is pinned through Swift Package Manager. Only the production bundle starts its updater. Check for Updates is available in the menu and About settings. The feed URL is the Latest release appcast asset on GitHub. A Tero-specific Ed25519 key lives in Keychain under account `tero-sparkle`; only the public key is embedded. Both the feed and update archive require signatures, and system profiling is disabled.

The pipeline exports the archive with Developer ID so Sparkle helper services are re-signed, notarizes the DMG, then uses the official generate_appcast tool to create a signed feed with embedded notes. It checks the build number, asset URL, length and signatures before uploading. Appcast generation is isolated from source archives. A public feed is never modified after signing. Never delete the Sparkle private key; use Sparkle's supported key-rotation process if needed.

The icon is the exact faceted three-bubble website logo in a black macOS tile, with a DEV label only for development. Source generator: Scripts/generate-app-icons.swift. Catalog contains all macOS 1×/2× icon sizes.

Changelog email delivery remains separate; this script does not send email.

Validation: targeted notarization/resume/rejection, immutable-publication, partial-upload and mismatched Sparkle key/feed tests. Real signed appcast generation and verification passed with a local synthetic DMG; a tampered feed was rejected. Dev build and universal Prod archive checked. First public notarized release and installation/update between two real notarized versions remain pending.

### Branded installer

Publication automatically creates the Finder layout through pinned `dmgbuild` tooling in an isolated local environment (never included in Tero). The disk uses Tero's compiled icon, a 660 × 420 Retina background, fixed Tero/Applications positions and a direct Applications link. Finder preferences are written into the image; no personal Finder settings are changed. Background artwork is generated by `Scripts/generate-installer-background.swift`. The completed image is signed, notarized and stapled before upload, exactly like the prior pipeline.
