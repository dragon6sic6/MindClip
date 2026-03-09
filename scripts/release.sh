#!/bin/bash
set -euo pipefail

# MindClip Release Script
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.4.0

VERSION="${1:?Usage: $0 <version>  (e.g. 1.4.0)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/../build"
PROJECT="$ROOT/MindClip.xcodeproj"
ENTITLEMENTS="$ROOT/MindClip.entitlements"
SIGNING_ID="Developer ID Application: Mindact Solutions AB (679J7H9973)"
KEYCHAIN_PROFILE="MindClip"
SPARKLE_BIN="/tmp/sparkle_tools/bin"
DOCS_DIR="$ROOT/docs"
DOWNLOAD_URL_PREFIX="https://github.com/dragon6sic6/MindClip/releases/download/v${VERSION}/"

echo "═══════════════════════════════════════════"
echo "  MindClip Release v${VERSION}"
echo "═══════════════════════════════════════════"

# ── 1. Build ──────────────────────────────────
echo ""
echo "▶ Step 1/8: Building..."
cd "$ROOT/.."
xcodebuild -project "$PROJECT" -scheme MindClip -configuration Release \
    -arch arm64 -arch x86_64 ONLY_ACTIVE_ARCH=NO \
    -derivedDataPath "$BUILD_DIR" clean build 2>&1 | tail -5

APP="$BUILD_DIR/Build/Products/Release/MindClip.app"
echo "  ✓ Build succeeded"

# ── 2. Re-sign (strip get-task-allow + deep-sign Sparkle) ─
echo ""
echo "▶ Step 2/8: Re-signing (deep)..."
# Sign Sparkle nested binaries first (deepest → outermost)
codesign --force --options runtime --timestamp --sign "$SIGNING_ID" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
codesign --force --options runtime --timestamp --sign "$SIGNING_ID" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
codesign --force --options runtime --timestamp --sign "$SIGNING_ID" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
codesign --force --options runtime --timestamp --sign "$SIGNING_ID" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
codesign --force --options runtime --timestamp --sign "$SIGNING_ID" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater"
codesign --force --options runtime --timestamp --sign "$SIGNING_ID" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
codesign --force --options runtime --timestamp --sign "$SIGNING_ID" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
codesign --force --options runtime --timestamp --sign "$SIGNING_ID" \
    "$APP/Contents/Frameworks/Sparkle.framework"
# Sign main app (with entitlements)
codesign --force --options runtime --timestamp --sign "$SIGNING_ID" \
    --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"
echo "  ✓ Signed (all binaries)"

# ── 3. Notarize app ──────────────────────────
echo ""
echo "▶ Step 3/8: Notarizing app..."
rm -f "$BUILD_DIR/MindClip_notarize.zip"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/MindClip_notarize.zip"
xcrun notarytool submit "$BUILD_DIR/MindClip_notarize.zip" \
    --keychain-profile "$KEYCHAIN_PROFILE" --wait
echo "  ✓ Notarized"

# ── 4. Staple app ────────────────────────────
echo ""
echo "▶ Step 4/8: Stapling app..."
xcrun stapler staple "$APP"
echo "  ✓ Stapled"

# ── 5. Build DMG ─────────────────────────────
echo ""
echo "▶ Step 5/8: Building DMG..."
rm -rf "$BUILD_DIR/dmg_staging/MindClip.app"
cp -R "$APP" "$BUILD_DIR/dmg_staging/"
rm -f "$BUILD_DIR/MindClip_rw.dmg" "$BUILD_DIR/MindClip.dmg"
hdiutil create -volname "MindClip" -srcfolder "$BUILD_DIR/dmg_staging" \
    -ov -format UDRW "$BUILD_DIR/MindClip_rw.dmg"
hdiutil attach "$BUILD_DIR/MindClip_rw.dmg" -readwrite -mountpoint /tmp/MindClipDMG
/usr/bin/SetFile -a C /tmp/MindClipDMG
hdiutil detach /tmp/MindClipDMG
hdiutil convert "$BUILD_DIR/MindClip_rw.dmg" -format UDZO \
    -o "$BUILD_DIR/MindClip.dmg" -ov
echo "  ✓ DMG created"

# ── 6. Notarize + staple DMG ─────────────────
echo ""
echo "▶ Step 6/8: Notarizing DMG..."
xcrun notarytool submit "$BUILD_DIR/MindClip.dmg" \
    --keychain-profile "$KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$BUILD_DIR/MindClip.dmg"
echo "  ✓ DMG notarized and stapled"

# ── 7. Upload to GitHub + generate appcast ───
echo ""
echo "▶ Step 7/8: Uploading to GitHub..."
cd "$ROOT"
gh release create "v${VERSION}" "$BUILD_DIR/MindClip.dmg" \
    --title "v${VERSION}" --notes "MindClip v${VERSION}" \
    2>/dev/null || \
gh release upload "v${VERSION}" "$BUILD_DIR/MindClip.dmg" --clobber
echo "  ✓ Uploaded to GitHub release v${VERSION}"

# ── 8. Generate appcast ──────────────────────
echo ""
echo "▶ Step 8/8: Generating appcast..."
if [ -x "$SPARKLE_BIN/generate_appcast" ]; then
    "$SPARKLE_BIN/generate_appcast" \
        --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
        -o "$DOCS_DIR/appcast.xml" \
        "$BUILD_DIR/MindClip.dmg"
    echo "  ✓ Appcast updated"
    echo ""
    echo "  ⚠  Remember to commit & push docs/appcast.xml:"
    echo "     git add docs/appcast.xml && git commit -m 'Update appcast for v${VERSION}' && git push"
else
    echo "  ⚠  Sparkle tools not found at $SPARKLE_BIN"
    echo "     Download with: curl -L https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-2.9.0.tar.xz | tar xJ -C /tmp/sparkle_tools"
fi

echo ""
echo "═══════════════════════════════════════════"
echo "  ✅ Release v${VERSION} complete!"
echo "═══════════════════════════════════════════"
