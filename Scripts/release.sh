#!/usr/bin/env bash
# release.sh — build, notarise, sign appcast, upload to R2
# Usage: bash Scripts/release.sh
set -euo pipefail

APP_NAME="Xe-Image Convert"
APP_SLUG="xe-image-convert"
BUNDLE_ID="com.ContiBros.Xe-Image-Convert"
APPCAST_BASE_URL="https://updates.xenon-post.com/${APP_SLUG}"
R2_BUCKET="xe-app-updates"
R2_PREFIX="${APP_SLUG}"
NOTARY_PROFILE="XenonNotary"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RELEASE_DIR="${PROJECT_DIR}/Releases"
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path "*/artifacts/sparkle/Sparkle/bin/generate_appcast" 2>/dev/null | head -1 | xargs dirname)"

if [[ -z "$SPARKLE_BIN" ]]; then
    echo "ERROR: Sparkle tools not found. Build the project in Xcode first."
    exit 1
fi

mkdir -p "$RELEASE_DIR"

echo "==> Building & archiving..."
xcodebuild -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
           -scheme "${APP_NAME}" \
           -configuration Release \
           -archivePath "${RELEASE_DIR}/${APP_NAME}.xcarchive" \
           clean archive

echo "==> Exporting..."
xcodebuild -exportArchive \
           -archivePath "${RELEASE_DIR}/${APP_NAME}.xcarchive" \
           -exportPath "${RELEASE_DIR}/Export" \
           -exportOptionsPlist "${SCRIPT_DIR}/ExportOptions.plist"

APP_PATH="${RELEASE_DIR}/Export/${APP_NAME}.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${APP_PATH}/Contents/Info.plist")
ZIP_NAME="${APP_SLUG}-${VERSION}.zip"
# Installer DMG is named with the app's display name + version (URL-safe form),
# per the studio "Installer DMG convention". The public download route and admin
# page resolve this filename from the appcast version — no per-release edit needed.
DMG_APP_NAME="Xe-Image-Convert"
DMG_NAME="${DMG_APP_NAME}-${VERSION}.dmg"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"
DMG_PATH="${RELEASE_DIR}/${DMG_NAME}"

echo "==> Version: ${VERSION} (${BUILD})"

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

echo "==> Creating DMG (with drag-to-install /Applications shortcut)..."
rm -f "$DMG_PATH"
DMG_STAGE="${RELEASE_DIR}/dmg_stage"
rm -rf "$DMG_STAGE" && mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$DMG_STAGE" \
    -ov -format UDZO \
    "$DMG_PATH"
rm -rf "$DMG_STAGE"

echo "==> Generating appcast..."
STAGING_DIR="${RELEASE_DIR}/appcast_staging"
rm -rf "$STAGING_DIR" && mkdir -p "$STAGING_DIR"
cp "${RELEASE_DIR}"/*.zip "$STAGING_DIR/"
"${SPARKLE_BIN}/generate_appcast" \
    "${STAGING_DIR}" \
    --download-url-prefix "${APPCAST_BASE_URL}/"
cp "${STAGING_DIR}/appcast.xml" "${RELEASE_DIR}/"

echo "==> Uploading to R2..."
wrangler r2 object put "${R2_BUCKET}/${R2_PREFIX}/appcast.xml" \
    --file "${RELEASE_DIR}/appcast.xml" \
    --content-type "application/xml" --remote

wrangler r2 object put "${R2_BUCKET}/${R2_PREFIX}/${ZIP_NAME}" \
    --file "$ZIP_PATH" \
    --content-type "application/zip" --remote

wrangler r2 object put "${R2_BUCKET}/${R2_PREFIX}/${DMG_NAME}" \
    --file "$DMG_PATH" \
    --content-type "application/x-apple-diskimage" --remote

# Graduate beta testers — publish this release to the beta feed too.
# Beta installs only poll the beta feed; this release points at the
# production feed, so after updating to it testers follow production.
# Skipped when no beta channel exists.
BETA_SLUG="${APP_SLUG}-beta"
BETA_STAGING="${PROJECT_DIR}/Releases-Beta/appcast_staging"
if [ -d "$BETA_STAGING" ] && ls "$BETA_STAGING"/*.zip >/dev/null 2>&1; then
    echo "==> Publishing ${VERSION} to the beta feed (graduating beta installs)..."
    cp "$ZIP_PATH" "$BETA_STAGING/"
    "${SPARKLE_BIN}/generate_appcast" "$BETA_STAGING" \
        --download-url-prefix "https://updates.xenon-post.com/${BETA_SLUG}/"

    TOP_BUILD=$(grep -o "<sparkle:version>[0-9]*</sparkle:version>" "$BETA_STAGING/appcast.xml" | head -1 | grep -o "[0-9]*")
    if [ "$TOP_BUILD" != "$BUILD" ]; then
        echo "WARNING: build ${BUILD} is not the newest in the beta appcast (newest: ${TOP_BUILD})."
        echo "         Beta installs will NOT update to this release — bump CURRENT_PROJECT_VERSION."
    fi

    wrangler r2 object put "${R2_BUCKET}/${BETA_SLUG}/${ZIP_NAME}" \
        --file "$ZIP_PATH" --content-type "application/zip" --remote
    for delta in "$BETA_STAGING"/*.delta; do
        [ -e "$delta" ] || continue
        wrangler r2 object put "${R2_BUCKET}/${BETA_SLUG}/$(basename "$delta")" \
            --file "$delta" --remote
    done
    wrangler r2 object put "${R2_BUCKET}/${BETA_SLUG}/appcast.xml" \
        --file "$BETA_STAGING/appcast.xml" --content-type "application/xml" --remote
fi

echo ""
echo "==> Done! v${VERSION} is live."
echo "    Appcast: ${APPCAST_BASE_URL}/appcast.xml"
echo "    DMG:     ${APPCAST_BASE_URL}/${DMG_NAME}"
