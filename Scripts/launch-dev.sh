#!/bin/bash
# Launch the signed development build from a stable, URL-addressable location.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
built_app="${1:-/tmp/tero-p0-build/Build/Products/Development/Tero Dev.app}"
launch_app="$(dirname "$project_dir")/DevApps/Tero Dev.app"
[[ -d "$built_app" ]] || { echo 'Build Tero Dev before launching.' >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$built_app"
# Stop only copies of this development build, never production Tero.
while read -r process_id executable; do
  case "$executable" in
    "$launch_app/Contents/MacOS/Tero Dev"|"$built_app/Contents/MacOS/Tero Dev"|"/private$built_app/Contents/MacOS/Tero Dev") ;;
    *) continue ;;
  esac
  kill -TERM "$process_id"
done < <(/bin/ps -axo pid=,command=)
mkdir -p "$(dirname "$launch_app")"
/usr/bin/ditto "$built_app" "$launch_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$launch_app"
/usr/bin/open -n "$launch_app"
echo 'Tero Dev launched from its stable development location.'
