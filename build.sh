#!/usr/bin/env bash
# Build Lingua Studio as a double-clickable .app on macOS (Xcode CLT required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "error: swiftc not found. Install Xcode or Command Line Tools:"
  echo "  xcode-select --install"
  exit 1
fi

ARCH="${TARGET_ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64|aarch64) TRIPLE="arm64-apple-macos13.0" ;;
  x86_64)        TRIPLE="x86_64-apple-macos13.0" ;;
  *) echo "error: unsupported arch $ARCH"; exit 1 ;;
esac

APP="$ROOT/LinguaStudio.app"
MACOS="$APP/Contents/MacOS"
mkdir -p "$MACOS"
mkdir -p "$APP/Contents/Resources"
cp -f Fixtures/sample.sdlxliff "$APP/Contents/Resources/" 2>/dev/null || true

# App icon: build AppIcon.icns from Resources/AppIcon-1024.png
if [ -f Resources/AppIcon-1024.png ]; then
  echo "==> Building app icon…"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s*2))
    sips -z $d $d Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

CORE_SOURCES=(
  Sources/LinguaCore/XMLHelpers.swift
  Sources/LinguaCore/WhitespacePreservingParser.swift
  Sources/LinguaCore/Models.swift
  Sources/LinguaCore/TagEngine.swift
  Sources/LinguaCore/Revisions.swift
  Sources/LinguaCore/SearchReplace.swift
  Sources/LinguaCore/History.swift
  Sources/LinguaCore/SDLXLIFFDocument.swift
  Sources/LinguaCore/FormattingResolver.swift
  Sources/LinguaCore/EditorSync.swift
  Sources/LinguaCore/IMEEditPolicy.swift
  Sources/LinguaCore/FlushPolicy.swift
  Sources/LinguaCore/FormatTagSupport.swift
  Sources/LinguaCore/SingleEditorPolicy.swift
)

UI_SOURCES=(
  Sources/LinguaStudio/LinguaApp.swift
  Sources/LinguaStudio/AppSettings.swift
  Sources/LinguaStudio/L10n.swift
  Sources/LinguaStudio/GeneralSettingsView.swift
  Sources/LinguaStudio/ReplaceSheetView.swift
  Sources/LinguaStudio/ContentView.swift
  Sources/LinguaStudio/Store.swift
  Sources/LinguaStudio/DisplayHelpers.swift
  Sources/LinguaStudio/RichSegmentEditor.swift
)

SDK="$(xcrun --show-sdk-path)"

echo "==> Compiling Lingua Studio ($TRIPLE)…"
swiftc -parse-as-library \
  -target "$TRIPLE" \
  -sdk "$SDK" \
  "${CORE_SOURCES[@]}" \
  "${UI_SOURCES[@]}" \
  -framework AppKit \
  -framework SwiftUI \
  -o "$MACOS/LinguaStudio"

chmod +x "$MACOS/LinguaStudio"
touch "$APP"  # refresh Finder/Dock icon cache

echo "==> Built: $APP"
echo "    Open with: open \"$APP\""
echo "    Or run:    \"$MACOS/LinguaStudio\""
echo ""
echo "Alternative (Swift Package Manager, Mac only):"
echo "    swift build -c release"
echo "    .build/release/LinguaStudio"
