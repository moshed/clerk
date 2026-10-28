#!/bin/bash
# Wait for a notarisation Apple has already accepted, then staple and install.
#
#   ./tools/finish-install.sh <submission-id>
#
# Exists because Apple's queue can sit "In Progress" for a long time, and
# `notarytool --wait` gives up with "deadlineExceeded" - which reads like the
# upload failed when it did not. Nothing is installed unless it is Accepted.
set -uo pipefail

# App Store Connect credentials live outside the repo: this is a public
# repository and the key id and issuer id identify the Apple account.
# ~/.private_keys/asc.env sets ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID.
if [ -z "${ASC_KEY_ID:-}" ] && [ -f "$HOME/.private_keys/asc.env" ]; then
  . "$HOME/.private_keys/asc.env"
fi
: "${ASC_KEY_PATH:?set ASC_KEY_PATH or create ~/.private_keys/asc.env}"
: "${ASC_KEY_ID:?set ASC_KEY_ID or create ~/.private_keys/asc.env}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID or create ~/.private_keys/asc.env}"
ID="${1:?a submission id}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/app/build/Build/Products/Release/Clerk.app"
KEY=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")

for _ in $(seq 1 180); do                       # up to about an hour
  STATUS=$(xcrun notarytool info "$ID" "${KEY[@]}" 2>&1 | awk '/status:/{print $2}')
  [ "$STATUS" = "Accepted" ] && break
  case "$STATUS" in Invalid|Rejected)
    echo "Apple refused it: $STATUS"
    xcrun notarytool log "$ID" "${KEY[@]}" 2>&1 | head -30
    exit 1;;
  esac
  sleep 20
done
[ "$STATUS" = "Accepted" ] || { echo "still $STATUS after an hour"; exit 1; }

xcrun stapler staple "$APP" || exit 1
pkill -x Clerk 2>/dev/null; sleep 1
ditto "$APP" /Applications/Clerk.app
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSR" -u "$APP" 2>/dev/null || true
open -a /Applications/Clerk.app
sleep 4
echo "installed build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  /Applications/Clerk.app/Contents/Info.plist)"
spctl -a -vv /Applications/Clerk.app 2>&1 | head -2
curl -s -o /dev/null -w "helper: %{http_code}\n" -X POST http://127.0.0.1:8771/profiles \
  -H "Content-Type: application/json" -d '{}'
curl -s -H "Title: Clerk installed" -d "Apple finally cleared the notarisation. The build with the Payment fields and the local-only Import button is installed." ntfy.sh/claude_dnz > /dev/null
