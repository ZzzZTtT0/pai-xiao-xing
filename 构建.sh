#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/派小星.app"
SRC="$ROOT/源码"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
cp "$SRC/资源/"* "$APP/Contents/Resources/"
PET_SDK="${PET_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
if [ ! -d "$PET_SDK" ]; then PET_SDK="$(/usr/bin/xcrun --show-sdk-path)"; fi
/usr/bin/swiftc -sdk "$PET_SDK" -swift-version 5 -O -target "$(uname -m)-apple-macos13.0" -framework Cocoa -framework QuartzCore "$SRC/Core.swift" "$SRC/PetDrawing.swift" "$SRC/PetApp.swift" "$SRC/Tests.swift" "$SRC/main.swift" -o "$APP/Contents/MacOS/PaiXiaoXing"
/usr/bin/codesign --force --sign - --timestamp=none "$APP"
mkdir -p "$ROOT/联动组件"
/usr/bin/swiftc -sdk "$PET_SDK" -swift-version 5 -O -target "$(uname -m)-apple-macos13.0" -framework Cocoa "$SRC/CodexAutoStart.swift" -o "$ROOT/联动组件/CodexAutoStart"
/usr/bin/codesign --force --sign - --timestamp=none "$ROOT/联动组件/CodexAutoStart"
printf '已构建：%s\n' "$APP"
