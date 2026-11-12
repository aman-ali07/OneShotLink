#!/usr/bin/env bash
# Regenerates the icon and social assets from their hand-authored sources.
# The outputs are committed, so this only runs when a source changes.
#
#   source                            output
#   site/favicon.svg  (transparent)    favicon.svg, favicon-16.png, favicon-32.png
#   site/app-icon.svg (opaque tile)    apple-touch-icon.png (180), icon-512.png,
#                                      site/app-icon-1024.png (store/brand asset)
#   site/og-card.html (1200x630)       og.png
#
# Icons go to site/ (landing deploy) and frontend/public/ (the app build copies
# that folder to the served root). Tools: rsvg-convert for the icons, Chrome for
# the card because it needs the real font stack and CSS layout. No network.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

die() { echo "build-assets: $*" >&2; exit 1; }

png_size() {
  local hex
  hex=$(od -An -tx1 -j16 -N8 "$1" | tr -d ' \n')
  printf '%sx%s' "$((16#${hex:0:8}))" "$((16#${hex:8:8}))"
}

command -v rsvg-convert >/dev/null || die "rsvg-convert not found (install librsvg2-bin)"

chrome="${CHROME_PATH:-}"
if [ -z "$chrome" ]; then
  for candidate in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "$candidate" >/dev/null; then chrome="$candidate"; break; fi
  done
fi
[ -n "$chrome" ] || die "no Chrome/Chromium found; set CHROME_PATH"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# stage the source so both destinations are written from a copy, never in place
install -m 644 site/favicon.svg "$work/favicon.svg"

rsvg-convert -w 16 -h 16 site/favicon.svg -o "$work/favicon-16.png"
rsvg-convert -w 32 -h 32 site/favicon.svg -o "$work/favicon-32.png"
rsvg-convert -w 180 -h 180 site/app-icon.svg -o "$work/apple-touch-icon.png"
rsvg-convert -w 512 -h 512 site/app-icon.svg -o "$work/icon-512.png"
rsvg-convert -w 1024 -h 1024 site/app-icon.svg -o "$work/app-icon-1024.png"

"$chrome" --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1200,630 \
  --screenshot="$work/og.png" "file://$root/site/og-card.html" >/dev/null 2>&1 ||
  die "Chrome failed to render site/og-card.html"

for dest in site frontend/public; do
  mkdir -p "$dest"
  install -m 644 "$work/favicon.svg" "$dest/favicon.svg"
  for name in favicon-16.png favicon-32.png apple-touch-icon.png icon-512.png og.png; do
    install -m 644 "$work/$name" "$dest/$name"
  done
done

install -m 644 "$work/app-icon-1024.png" site/app-icon-1024.png

echo "build-assets: wrote"
for dest in site frontend/public; do
  for name in favicon.svg favicon-16.png favicon-32.png apple-touch-icon.png icon-512.png og.png; do
    if [ "${name##*.}" = "svg" ]; then
      printf '  %-40s svg\n' "$dest/$name"
    else
      printf '  %-40s %s\n' "$dest/$name" "$(png_size "$dest/$name")"
    fi
  done
done
printf '  %-40s %s\n' "site/app-icon-1024.png" "$(png_size site/app-icon-1024.png)"
