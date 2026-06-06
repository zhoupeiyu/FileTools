#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PNG="$ROOT/assets/icon/app_icon_1024.png"
MAC_DIR="$ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset"
WIN_ICO="$ROOT/windows/runner/resources/app_icon.ico"

command -v magick >/dev/null 2>&1 || {
  echo "ImageMagick is required: brew install imagemagick" >&2
  exit 1
}

mkdir -p "$ROOT/assets/icon" "$MAC_DIR" "$(dirname "$WIN_ICO")"

magick -size 1024x1024 xc:none \
  -fill "#0b6470" -draw "roundrectangle 52,52 972,972 216,216" \
  -fill "#0f9b91" -draw "roundrectangle 52,52 972,520 216,216" \
  -fill "#193b4d55" -draw "ellipse 726,828 360,190 0,360" \
  -fill "#e2fbf633" -draw "ellipse 326,244 250,160 0,360" \
  -fill "#00000030" -draw "roundrectangle 302,222 722,800 72,72" \
  -fill "#f8fbfa" -draw "roundrectangle 286,204 706,782 72,72" \
  -fill "#d9eeee" -draw "polygon 548,204 706,362 548,362" \
  -stroke "#b7d8d5" -strokewidth 10 -fill none -draw "path 'M548 204 L548 324 Q548 362 586 362 L706 362'" \
  -stroke none -fill "#c7d9d7" -draw "roundrectangle 374,486 618,516 15,15" \
  -fill "#c7d9d7" -draw "roundrectangle 374,568 650,598 15,15" \
  -fill "#c7d9d7" -draw "roundrectangle 374,650 572,680 15,15" \
  -fill none -stroke "#f4c15d" -strokewidth 44 -draw "path 'M322 584 L232 512 L322 440'" \
  -draw "path 'M690 440 L782 512 L690 584'" \
  -stroke "#f4c15d" -strokewidth 34 -draw "line 388,512 626,512" \
  "$PNG"

for size in 16 32 64 128 256 512 1024; do
  magick "$PNG" -resize "${size}x${size}" "$MAC_DIR/app_icon_${size}.png"
done

magick "$PNG" -define icon:auto-resize=256,128,64,48,32,16 "$WIN_ICO"

echo "Generated app icons at $PNG"
