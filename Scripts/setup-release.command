#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
printf 'One-time Apple notarization setup. Your password stays in the macOS Keychain.\n'
printf 'Generate an app-specific password at https://account.apple.com → Sign-In and Security → App-Specific Passwords.\n'
open 'https://account.apple.com'
read -r -p 'Apple Developer account email: ' release_apple_id
xcrun notarytool store-credentials tero-notary --apple-id "$release_apple_id" --team-id 52WH9VZ63T
python3 Scripts/publish-release.py --check
printf '\nSetup complete. Future releases need no credential entry.\n'
read -r -p 'Press Return to close…' ignored
