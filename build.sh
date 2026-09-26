#!/bin/bash
set -eo pipefail

cd "$(dirname "$0")"

# Build products live in build.noindex/: Spotlight skips folders ending in .noindex,
# so build copies of the app never show up next to the installed one (T-0031)
DERIVED_DATA="build.noindex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Remove build copies of the app from Launch Services (the "Open with" / Apps list).
# Only paths under the build folders — never the installed app.
unregister_build_copies() {
    local app
    for app in "$DERIVED_DATA"/Build/Products/*/GameTranslator.app build/Build/Products/*/GameTranslator.app; do
        [ -d "$app" ] && "$LSREGISTER" -u "$app" 2>/dev/null || true
    done
}

# --- Pick a code signing identity ---
# A real certificate keeps the app's identity stable across rebuilds, so macOS
# remembers Keychain "Always Allow" and the Screen Recording permission.
# Ad-hoc signing ("-") creates a new identity every build and macOS asks again.
# Override with: SIGN_IDENTITY="Apple Development: Name (TEAMID)" ./build.sh
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -E '"(Apple Development|Developer ID Application|GameTranslator Local Signing)' \
        | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "⚠️  ไม่พบ certificate สำหรับ sign — ใช้ ad-hoc (macOS จะถามสิทธิ์ Keychain/Screen Recording ใหม่ทุกครั้งที่ build)"
else
    echo "🔏 Sign ด้วย: $SIGN_IDENTITY"
fi

echo "🔧 Generating Xcode project..."
xcodegen generate

echo ""
echo "🏗️ Building GameTranslator (Release)..."
xcodebuild -project GameTranslator.xcodeproj \
    -scheme GameTranslator \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY="-" \
    clean build

APP_PATH="$DERIVED_DATA/Build/Products/Release/GameTranslator.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build ล้มเหลว — ไม่พบ .app"
    exit 1
fi

EXEC_PATH="$APP_PATH/Contents/MacOS/GameTranslator"
if [ ! -f "$EXEC_PATH" ]; then
    echo "❌ Build ล้มเหลว — ไม่พบ executable"
    echo "   ตรวจสอบ error ด้านบน"
    exit 1
fi

echo ""
echo "✅ Build สำเร็จ!"
echo ""

# --- Remove ALL existing copies first ---
echo "🗑️  ลบแอพเก่าทั้งหมด..."
if [ -d "$HOME/Applications/GameTranslator.app" ]; then
    rm -rf "$HOME/Applications/GameTranslator.app"
    echo "   ลบ ~/Applications/GameTranslator.app"
fi
if [ -w "/Applications" ] && [ -d "/Applications/GameTranslator.app" ]; then
    rm -rf "/Applications/GameTranslator.app"
    echo "   ลบ /Applications/GameTranslator.app"
fi

# --- Determine install destination ---
DEST="/Applications"
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi

TARGET="$DEST/GameTranslator.app"

# --- Install ---
cp -R "$APP_PATH" "$TARGET"
echo "📦 ลงที่ $TARGET"

# --- Clean build output to avoid duplicates in Spotlight / Apps ---
# (also the Debug test host left by Verify, and copies in the old build/ folder)
unregister_build_copies
rm -rf "$APP_PATH" build/Build/Products/*/GameTranslator.app
echo "🧹 ลบ build output .app (ป้องกันแอพซ้ำใน Spotlight)"

# --- Sign with entitlements ---
# A failed or wrong signature must stop here, before the running app is killed or
# the new one launched: an app not signed with the certificate gets a new identity
# and macOS asks for Screen Recording permission again.
sign_failed() {
    echo ""
    echo "❌ Sign ไม่สำเร็จ ($SIGN_IDENTITY) — หยุด build (ไม่ปิดแอพเดิม ไม่เปิดแอพใหม่)"
    echo "$1" | sed 's/^/   /'
    echo ""
    echo "   ⚠️  $TARGET ที่ลงไปแล้วยังไม่ได้ sign ด้วย certificate ที่ถูกต้อง"
    echo "      อย่าเปิดตัวนี้ (macOS จะถามสิทธิ์ Screen Recording ใหม่) — แก้แล้วรัน ./build.sh อีกครั้ง"
    echo "   ดู certificate ที่มี: security find-identity -v -p codesigning"
    exit 1
}

ENT="Resources/GameTranslator.entitlements"
SIGN_ARGS=(--force --deep --sign "$SIGN_IDENTITY")
if [ -f "$ENT" ]; then
    SIGN_ARGS+=(--entitlements "$ENT")
fi
SIGN_ARGS+=(--timestamp=none)

if ! SIGN_OUTPUT=$(codesign "${SIGN_ARGS[@]}" "$TARGET" 2>&1); then
    sign_failed "$SIGN_OUTPUT"
fi
if [ -n "$SIGN_OUTPUT" ]; then
    echo "$SIGN_OUTPUT"
fi

# --- Verify the signature (certificate builds only; ad-hoc is the known fallback) ---
if [ "$SIGN_IDENTITY" != "-" ]; then
    if ! VERIFY_OUTPUT=$(codesign --verify --deep --strict "$TARGET" 2>&1); then
        sign_failed "codesign --verify: $VERIFY_OUTPUT"
    fi
    if ! SIGN_INFO=$(codesign -dvv "$TARGET" 2>&1); then
        sign_failed "codesign -dvv: $SIGN_INFO"
    fi
    if echo "$SIGN_INFO" | grep -q "^Signature=adhoc"; then
        sign_failed "แอพยังเป็น ad-hoc signature ไม่ใช่ $SIGN_IDENTITY"
    fi
    # An identity given as a SHA-1 hash can't be matched by name — the ad-hoc check covers it
    if ! [[ "$SIGN_IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]] \
        && ! echo "$SIGN_INFO" | grep -qxF "Authority=$SIGN_IDENTITY"; then
        sign_failed "ผู้ sign ไม่ตรงกับ $SIGN_IDENTITY:
$(echo "$SIGN_INFO" | grep '^Authority=' || echo '(ไม่มี Authority)')"
    fi
    echo "✅ ตรวจ signature แล้ว — sign ด้วย $SIGN_IDENTITY"
fi
echo "🔏 Signed ($SIGN_IDENTITY)"

# --- Clear quarantine attribute ---
xattr -cr "$TARGET"
echo "🧹 Cleared quarantine attribute"

# --- Kill old instance if running ---
killall GameTranslator 2>/dev/null && echo "🔄 ปิดแอพเก่า" && sleep 1 || true

# --- Reset stale TCC entries for this bundle ID ---
# Ad-hoc signing creates a new code signature each build, leaving
# stale entries in the Screen Recording permission list.
# Only needed for ad-hoc builds — a stable certificate keeps the existing grant.
if [ "$SIGN_IDENTITY" = "-" ]; then
    tccutil reset ScreenCapture com.worawalan.GameTranslator 2>/dev/null || true
    echo "🔑 ล้าง Screen Recording permission เก่า (ป้องกัน entry ซ้ำ)"
fi

echo ""
echo "🚀 เปิดแอพ..."
open "$TARGET"

echo ""
echo "✅ เสร็จสิ้น! แอพ GameTranslator พร้อมใช้งาน"
echo ""
echo "⚠️  ถ้าเปิดไม่ได้ (แสดงไอคอนห้าม):"
echo "   1. คลิกขวาที่แอพ → Open"
echo "   2. หรือไปที่ System Settings → Privacy & Security → แล้วกด Open Anyway"
