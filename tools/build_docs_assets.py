import os
from PIL import Image, ImageDraw

scratch = os.environ.get("TMPDIR", "/tmp")
pairs = [
    ("renders/final_action_v2.png", "docs/assets/shot_combat.jpg"),
    ("renders/final_peaceful.png", "docs/assets/shot_peaceful.jpg"),
    ("renders/final_title.png", "docs/assets/shot_title.jpg"),
    ("renders/final_help.png", "docs/assets/shot_help.jpg"),
    (os.path.join(scratch, "storm.png"), "docs/assets/shot_storm.jpg"),
    (os.path.join(scratch, "ember.png"), "docs/assets/shot_ember.jpg"),
    ("renders/enemies_v2_compare.png", "docs/assets/craft_v1_vs_v2.jpg"),
    ("renders/sides_v2_all.jpg", "docs/assets/sides_v2_all.jpg"),
]
for src, dst in pairs:
    im = Image.open(src).convert("RGB")
    im.save(dst, quality=88, optimize=True)

combat = Image.open("renders/final_action_v2.png").convert("RGB")
w, h = combat.size
target_ratio = 1200 / 630
new_h = int(w / target_ratio)
top = max((h - new_h) // 2, 0)
og = combat.crop((0, top, w, top + new_h)).resize((1200, 630), Image.LANCZOS)
og.save("docs/assets/og-share.jpg", quality=87, optimize=True)

bg = Image.open("game/assets/art/backdrop.png").convert("RGBA").resize((512, 512), Image.LANCZOS)
fg = Image.open("concepts/batch1/player_ostrich_concept.png").convert("RGBA")
px = fg.load()
fw, fh = fg.size
for y in range(fh):
    for x in range(fw):
        r, g, b, a = px[x, y]
        mx, mn = max(r, g, b), min(r, g, b)
        if mx > 235 and (mx - mn) < 18:
            px[x, y] = (r, g, b, 0)
        elif mx > 215 and (mx - mn) < 14:
            px[x, y] = (r, g, b, int(a * 0.35))
fg = fg.resize((448, 448), Image.LANCZOS)
badge = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
mask = Image.new("L", (512, 512), 0)
ImageDraw.Draw(mask).rounded_rectangle((12, 12, 500, 500), radius=108, fill=255)
badge.paste(bg, (0, 0), mask)
badge.alpha_composite(fg, (32, 38))
badge.save("docs/assets/icon-512.png")
badge.resize((180, 180), Image.LANCZOS).save("docs/assets/apple-touch-icon.png")
badge.resize((32, 32), Image.LANCZOS).save("docs/assets/favicon-32.png")
print("DOCS ASSETS BUILT")
