#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${SKYJOUST_APP_DIR:-$HOME/Games/Skyjoust}"
APP="$OUT_DIR/Skyjoust.app"
ICONSET="${TMPDIR:-/tmp}/Skyjoust.iconset"

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

# Build crisp rounded-square macOS app icon from player_ostrich concept + Sunset Isles palette
env -u PYTHONPATH uv run -q --with pillow python - "$ROOT" "$ICONSET" <<'PY'
import sys
from PIL import Image, ImageDraw

root, iconset = sys.argv[1], sys.argv[2]
bg = Image.open(f"{root}/game/assets/art/backdrop.png").convert("RGBA").resize((1024, 1024), Image.LANCZOS)
fg = Image.open(f"{root}/concepts/batch1/player_ostrich_concept.png").convert("RGBA")
# Remove near-white studio background from concept art cleanly
px = fg.load()
w, h = fg.size
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        mx, mn = max(r, g, b), min(r, g, b)
        if mx > 235 and (mx - mn) < 18:
            px[x, y] = (r, g, b, 0)
        elif mx > 215 and (mx - mn) < 14:
            px[x, y] = (r, g, b, int(a * 0.35))
fg = fg.resize((880, 880), Image.LANCZOS)
canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
mask = Image.new("L", (1024, 1024), 0)
ImageDraw.Draw(mask).rounded_rectangle((24, 24, 1000, 1000), radius=215, fill=255)
canvas.paste(bg, (0, 0), mask)
canvas.alpha_composite(fg, (72, 82))
for sz in (16, 32, 128, 256, 512):
    canvas.resize((sz, sz), Image.LANCZOS).save(f"{iconset}/icon_{sz}x{sz}.png")
    canvas.resize((sz * 2, sz * 2), Image.LANCZOS).save(f"{iconset}/icon_{sz}x{sz}@2x.png")
PY

iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Skyjoust</string>
  <key>CFBundleExecutable</key>
  <string>Skyjoust</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.charles-forsyth.skyjoust</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Skyjoust</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

cat > "$APP/Contents/MacOS/Skyjoust" <<EOF
#!/usr/bin/env bash
unset PYTHONPATH
exec /Applications/Godot.app/Contents/MacOS/Godot --path "$ROOT/game" "\$@"
EOF
chmod +x "$APP/Contents/MacOS/Skyjoust"
xattr -cr "$APP" || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"
