#!/bin/bash
# Build build/AppIcon.icns from a source image in Resources/.
# Priority: 1) PNG (transparent, best)   2) SVG (rendered)
# Output: a master 1024x1024 PNG downsized into an .iconset -> .icns
set -e

ICNS="build/AppIcon.icns"
ICONSET="build/icon.iconset"
MASTER="build/icon_master.png"

# --- locate source: prefer a PNG, then the SVG -------------------------------
PNG_SRC=""
for f in "Resources/AppIcon.png" "Resources/SyncLight Pro.png"; do
    [ -f "$f" ] && { PNG_SRC="$f"; break; }
done
SVG_SRC="Resources/SyncLight Pro.svg"

if [ -z "$PNG_SRC" ] && [ ! -f "$SVG_SRC" ]; then
    echo "==> No icon source (Resources/AppIcon.png or SyncLight Pro.svg), skipping."
    exit 0
fi

mkdir -p build
rm -f "$ICNS"

if [ -n "$PNG_SRC" ]; then
    echo "==> Using PNG source: $PNG_SRC"
    # Normalise to a 1024x1024 master, preserving alpha.
    sips -s format png -z 1024 1024 "$PNG_SRC" --out "$MASTER" >/dev/null
else
    echo "==> Rendering SVG source: $SVG_SRC"
    if command -v rsvg-convert >/dev/null 2>&1; then
        rsvg-convert -w 1024 -h 1024 "$SVG_SRC" -o "$MASTER"
    elif command -v cairosvg >/dev/null 2>&1; then
        cairosvg "$SVG_SRC" -W 1024 -H 1024 -o "$MASTER"
    elif command -v magick >/dev/null 2>&1; then
        magick -background none "$SVG_SRC" -resize 1024x1024 "$MASTER"
    else
        tmpdir="$(mktemp -d)"
        qlmanage -t -s 1024 -o "$tmpdir" "$SVG_SRC" >/dev/null 2>&1 || true
        png="$(/bin/ls "$tmpdir"/*.png 2>/dev/null | head -1)"
        if [ -z "$png" ]; then
            echo "!! No SVG renderer. Install:  brew install librsvg" >&2
            rm -rf "$tmpdir"; exit 1
        fi
        sips -s format png "$png" --out "$MASTER" >/dev/null
        rm -rf "$tmpdir"
    fi
fi

# --- build the .iconset ------------------------------------------------------
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$MASTER" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s*2))
    sips -z "$d" "$d" "$MASTER" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "==> Wrote $ICNS"
