#!/bin/bash
set -eo pipefail

cd "$(dirname "$0")"

echo "🔧 Generating Xcode project..."
xcodegen generate

echo ""
echo "🏗️ Building GameTranslator (Release)..."
xcodebuild -project GameTranslator.xcodeproj \
    -scheme GameTranslator \
    -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="-" \
    clean build

APP_PATH="build/Build/Products/Release/GameTranslator.app"

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

# --- Clean build output to avoid duplicate in Spotlight ---
rm -rf "$APP_PATH"
touch build/.metadata_never_index 2>/dev/null || true
echo "🧹 ลบ build output .app (ป้องกันแอพซ้ำใน Spotlight)"

# --- Ad-hoc sign with entitlements ---
ENT="Resources/GameTranslator.entitlements"
if [ -f "$ENT" ]; then
    codesign --force --deep --sign - --entitlements "$ENT" --timestamp=none "$TARGET" 2>&1 || true
    echo "🔏 Ad-hoc signed with entitlements"
else
    codesign --force --deep --sign - --timestamp=none "$TARGET" 2>&1 || true
    echo "🔏 Ad-hoc signed"
fi

# --- Clear quarantine attribute ---
xattr -cr "$TARGET"
echo "🧹 Cleared quarantine attribute"

# --- Kill old instance if running ---
killall GameTranslator 2>/dev/null && echo "🔄 ปิดแอพเก่า" && sleep 1 || true

# --- Reset stale TCC entries for this bundle ID ---
# Ad-hoc signing creates a new code signature each build, leaving
# stale entries in the Screen Recording permission list.
tccutil reset ScreenCapture com.worawalan.GameTranslator 2>/dev/null || true
echo "🔑 ล้าง Screen Recording permission เก่า (ป้องกัน entry ซ้ำ)"

echo ""
echo "🚀 เปิดแอพ..."
open "$TARGET"

echo ""
echo "✅ เสร็จสิ้น! แอพ GameTranslator พร้อมใช้งาน"
echo ""
echo "⚠️  ถ้าเปิดไม่ได้ (แสดงไอคอนห้าม):"
echo "   1. คลิกขวาที่แอพ → Open"
echo "   2. หรือไปที่ System Settings → Privacy & Security → แล้วกด Open Anyway"
