#!/usr/bin/env bash
# release-beta.sh — beta-channel build for the xe-image-convert-beta feed,
# served to testers at xenon-post.com/beta.
#
# Usage: bash Scripts/release-beta.sh <version> <build>
#   e.g. bash Scripts/release-beta.sh 1.5b1 2
# <build> (CFBundleVersion) must be higher than any shipped build — Sparkle
# compares build numbers. NOTE: production has shipped with build 1 so far,
# so the next production release must use a build higher than the last beta.
#
# The feed URL is overridden on the command line (INFOPLIST_KEY_SUFeedURL),
# so no Xcode project changes are needed; release builds keep the production
# feed. Graduation happens automatically via the step in release.sh.
set -euo pipefail

APP_NAME="Xe-Image Convert"
APP_SLUG="xe-image-convert"
BETA_SLUG="${APP_SLUG}-beta"
APPCAST_BASE_URL="https://updates.xenon-post.com/${BETA_SLUG}"
R2_BUCKET="xe-app-updates"
NOTARY_PROFILE="XenonNotary"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RELEASE_DIR="${PROJECT_DIR}/Releases-Beta"
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path "*/artifacts/sparkle/Sparkle/bin/generate_appcast" 2>/dev/null | head -1 | xargs dirname)"

VERSION="${1:?usage: release-beta.sh <version> <build>   e.g. 1.5b1 2}"
BUILD="${2:?usage: release-beta.sh <version> <build>   e.g. 1.5b1 2}"

if [[ -z "$SPARKLE_BIN" ]]; then
    echo "ERROR: Sparkle tools not found. Build the project in Xcode first."
    exit 1
fi

mkdir -p "$RELEASE_DIR"

echo "==> Building & archiving ${VERSION} (build ${BUILD}, beta feed)..."
xcodebuild -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
           -scheme "${APP_NAME}" \
           -configuration Release \
           -archivePath "${RELEASE_DIR}/${APP_NAME}.xcarchive" \
           MARKETING_VERSION="$VERSION" \
           CURRENT_PROJECT_VERSION="$BUILD" \
           XE_SU_FEED_URL="${APPCAST_BASE_URL}/appcast.xml" \
           clean archive

echo "==> Exporting..."
xcodebuild -exportArchive \
           -archivePath "${RELEASE_DIR}/${APP_NAME}.xcarchive" \
           -exportPath "${RELEASE_DIR}/Export" \
           -exportOptionsPlist "${SCRIPT_DIR}/ExportOptions.plist"

APP_PATH="${RELEASE_DIR}/Export/${APP_NAME}.app"

# Guard: exported app must point at the beta feed
FEED=$(/usr/libexec/PlistBuddy -c "Print SUFeedURL" "${APP_PATH}/Contents/Info.plist")
if [[ "$FEED" != *"${BETA_SLUG}"* ]]; then
    echo "ERROR: SUFeedURL is '$FEED' — expected the ${BETA_SLUG} feed. Aborting."
    exit 1
fi

ZIP_NAME="${APP_SLUG}-${VERSION}.zip"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"

echo "==> Zipping for notarisation..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Notarising..."
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling..."
xcrun stapler staple "$APP_PATH"

echo "==> Re-zipping after staple..."
rm "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Generating appcast..."
STAGING_DIR="${RELEASE_DIR}/appcast_staging"
mkdir -p "$STAGING_DIR"
cp "$ZIP_PATH" "$STAGING_DIR/"
"${SPARKLE_BIN}/generate_appcast" \
    "${STAGING_DIR}" \
    --download-url-prefix "${APPCAST_BASE_URL}/"
cp "${STAGING_DIR}/appcast.xml" "${RELEASE_DIR}/"

echo "==> Uploading to R2 (zip first, appcast last)..."
wrangler r2 object put "${R2_BUCKET}/${BETA_SLUG}/${ZIP_NAME}" \
    --file "$ZIP_PATH" \
    --content-type "application/zip" --remote
for delta in "${STAGING_DIR}"/*.delta; do
    [ -e "$delta" ] || continue
    wrangler r2 object put "${R2_BUCKET}/${BETA_SLUG}/$(basename "$delta")" \
        --file "$delta" --remote
done
wrangler r2 object put "${R2_BUCKET}/${BETA_SLUG}/appcast.xml" \
    --file "${RELEASE_DIR}/appcast.xml" \
    --content-type "application/xml" --remote

echo ""
echo "==> Done! v${VERSION} (beta) is live."
echo "    Appcast:     ${APPCAST_BASE_URL}/appcast.xml"
echo "    Tester page: https://xenon-post.com/beta"
