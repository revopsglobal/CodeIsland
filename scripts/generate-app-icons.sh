#!/bin/bash

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
SOURCE_DIRECTORY="$REPOSITORY_ROOT/Design/AppIcon"
LEGACY_DIRECTORY="$SOURCE_DIRECTORY/Legacy"
ICON_DIRECTORY="$REPOSITORY_ROOT/ios/CodeIslandCompanion/CodeIslandCompanion/Assets.xcassets/AppIcon.appiconset"

mkdir -p "$LEGACY_DIRECTORY"

render_master() {
    local source="$1"
    local destination="$2"
    local temporary="${destination%.png}-rgba.png"
    sips -s format png "$source" --out "$temporary" >/dev/null
    /usr/bin/swift "$SCRIPT_DIRECTORY/make-opaque-png.swift" "$temporary" "$destination"
    rm "$temporary"
}

render_legacy() {
    local filename="$1"
    local pixels="$2"
    sips -z "$pixels" "$pixels" "$ICON_DIRECTORY/AppIcon-Light-1024.png" \
        --out "$LEGACY_DIRECTORY/$filename" >/dev/null
}

render_master "$SOURCE_DIRECTORY/paired-signal-light.svg" "$ICON_DIRECTORY/AppIcon-Light-1024.png"
render_master "$SOURCE_DIRECTORY/paired-signal-dark.svg" "$ICON_DIRECTORY/AppIcon-Dark-1024.png"
render_master "$SOURCE_DIRECTORY/paired-signal-tinted.svg" "$ICON_DIRECTORY/AppIcon-Tinted-1024.png"

# Modern Xcode derives runtime icon sizes from the universal masters. Keep
# small-size inspection renders outside the asset set so actool has no
# unassigned children from the retired legacy catalog.
rm -f "$ICON_DIRECTORY"/Icon-*.png

render_legacy "Icon-20x20@1x.png" 20
render_legacy "Icon-20x20@2x.png" 40
render_legacy "Icon-20x20@3x.png" 60
render_legacy "Icon-29x29@1x.png" 29
render_legacy "Icon-29x29@2x.png" 58
render_legacy "Icon-29x29@3x.png" 87
render_legacy "Icon-40x40@1x.png" 40
render_legacy "Icon-40x40@2x.png" 80
render_legacy "Icon-40x40@3x.png" 120
render_legacy "Icon-60x60@2x.png" 120
render_legacy "Icon-60x60@3x.png" 180
render_legacy "Icon-76x76@1x.png" 76
render_legacy "Icon-76x76@2x.png" 152
render_legacy "Icon-83.5x83.5@2x.png" 167

LIGHT_HASH="$(shasum -a 256 "$ICON_DIRECTORY/AppIcon-Light-1024.png" | awk '{print $1}')"
DARK_HASH="$(shasum -a 256 "$ICON_DIRECTORY/AppIcon-Dark-1024.png" | awk '{print $1}')"
TINTED_HASH="$(shasum -a 256 "$ICON_DIRECTORY/AppIcon-Tinted-1024.png" | awk '{print $1}')"

printf '{\n  "AppIcon-Light-1024.png": "%s",\n  "AppIcon-Dark-1024.png": "%s",\n  "AppIcon-Tinted-1024.png": "%s"\n}\n' \
    "$LIGHT_HASH" "$DARK_HASH" "$TINTED_HASH" > "$SOURCE_DIRECTORY/manifest.json"

echo "Generated Paired Signal app icons in $ICON_DIRECTORY"
