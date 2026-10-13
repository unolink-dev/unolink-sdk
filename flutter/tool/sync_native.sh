#!/bin/sh
# Copies the native SDK cores (../ios, ../android) into this plugin, so the package is self-contained.
# Run before `flutter pub publish` and after changing either SDK.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
repo=$(cd "$here/.." && pwd)
rm -rf "$here/ios/UnolinkCore" "$here/android/src/main/kotlin/dev/unolink/core"
cp -R "$repo/ios/Sources/Unolink" "$here/ios/UnolinkCore"
mkdir -p "$here/android/src/main/kotlin/dev/unolink"
cp -R "$repo/android/unolink/src/main/java/dev/unolink" "$here/android/src/main/kotlin/dev/unolink/core"
echo "Synced native SDK cores into the Flutter plugin."
