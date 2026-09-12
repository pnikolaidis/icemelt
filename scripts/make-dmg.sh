#!/bin/bash
#
# Builds the distributable DMG: a drag-to-Applications window showing IceMelt.app
# beside an Applications shortcut, over dmg/background.tiff.
#
# Usage: scripts/make-dmg.sh <path-to-IceMelt.app> [output.dmg]
#
# Defaults the output to dist/IceMelt-<version>.dmg, taking the version from the
# app's CFBundleShortVersionString. Signs the DMG when CODESIGN_IDENTITY is set
# or the fleet Developer ID is available; notarizing and stapling stay with the
# release flow, and must happen *after* this script (stapling rewrites the DMG).
#
# The window geometry is the Scratch Itch fleet standard, shared with cmdtab,
# hostbar, moonphase, olympus, iCloudWatch and fnmute: a {400, 120, 1040, 548}
# window, 128pt icons, app at (160, 190) and Applications at (480, 190).
# Icon positions must match the arrow in dmg/background.tiff — regenerate it
# with `swift scripts/make-dmg-background.swift` if you move them.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: scripts/make-dmg.sh <path-to-IceMelt.app> [output.dmg]}"
[[ -d "$APP" ]] || { echo "error: no app bundle at $APP" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="${2:-dist/IceMelt-${VERSION}.dmg}"
VOL="IceMelt ${VERSION}"
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Paradigm Consulting Company (VZGXGAK29Q)}"

[[ -f dmg/background.tiff ]] || {
    echo "error: dmg/background.tiff missing — run: swift scripts/make-dmg-background.swift" >&2
    echo "       then: tiffutil -cathidpicheck dmg/background.png dmg/background@2x.png -out dmg/background.tiff" >&2
    exit 1
}

mkdir -p "$(dirname "$DMG")"
STAGE="$(mktemp -d)"
RW="${STAGE}-rw.dmg"
trap 'rm -rf "${STAGE}" "${RW}"; hdiutil detach "/Volumes/${VOL}" >/dev/null 2>&1 || true' EXIT

echo "==> staging ${VERSION}"
cp -R "$APP" "${STAGE}/IceMelt.app"
ln -s /Applications "${STAGE}/Applications"
mkdir "${STAGE}/.background"
cp dmg/background.tiff "${STAGE}/.background/background.tiff"

# HFS+ and read-write, so Finder can write the layout into the volume's .DS_Store.
hdiutil create -srcfolder "${STAGE}" -volname "${VOL}" -fs HFS+ -format UDRW -quiet "${RW}"
hdiutil attach "${RW}" -noautoopen -quiet

echo "==> applying Finder layout"
# Needs the Automation->Finder permission once. If it's denied the DMG still
# works, just with Finder's default layout instead of the drag-install window.
if ! osascript <<EOF
tell application "Finder"
    tell disk "${VOL}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 120, 1040, 548}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "IceMelt.app" to {160, 190}
        set position of item "Applications" to {480, 190}
        -- Park hidden housekeeping items below the window so the layout stays
        -- clean for users who show hidden files. Errors here don't matter
        -- (items may be invisible to Finder when hidden files are off).
        try
            set position of item ".background" to {160, 700}
        end try
        try
            set position of item ".fseventsd" to {480, 700}
        end try
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF
then
    echo "WARN: Finder layout failed (Automation permission?); default layout kept" >&2
fi

sync
hdiutil detach "/Volumes/${VOL}" -quiet
echo "==> compressing"
hdiutil convert "${RW}" -format UDZO -imagekey zlib-level=9 -o "${DMG}" -ov -quiet

if security find-identity -v -p codesigning | grep -q "${IDENTITY}"; then
    echo "==> signing DMG"
    codesign --force --sign "${IDENTITY}" --timestamp "${DMG}"
else
    echo "WARN: signing identity not found, leaving DMG unsigned: ${IDENTITY}" >&2
fi

echo "==> ${DMG}"
shasum -a 256 "${DMG}"
