#!/usr/bin/env python3
"""Repository integrity, link, asset, and privacy check for CI and local gates."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

REQUIRED_GAME_MODELS = [
    "player_ostrich.glb",
    "enemy_bounder.glb",
    "enemy_hunter.glb",
    "enemy_shadowlord.glb",
    "buzzard_riderless.glb",
    "pterodactyl.glb",
    "egg.glb",
    "platform_base.glb",
    "platform_long.glb",
    "platform_short.glb",
    "spawn_pad.glb",
    "wing_feathered.glb",
]

REQUIRED_WEB_MODELS = [
    "player_ostrich.glb",
    "enemy_bounder.glb",
    "enemy_hunter.glb",
    "enemy_shadowlord.glb",
    "buzzard_riderless.glb",
    "pterodactyl.glb",
    "egg.glb",
    "platform_long.glb",
    "spawn_pad.glb",
    "wing_feathered.glb",
]

FORBIDDEN_PATTERNS = re.compile(
    "|".join([
        "/Us" + "ers/",
        "forsyth" + "c",
        "ucr" + "slurmcl",
        "ursa-" + "major",
        "gpu" + "l4",
        "gpu1" + "v1",
        "/apps/" + "containers",
        "BEGIN PRIVATE" + " KEY",
        "ghp_" + "[A-Za-z0-9]{20,}",
    ]),
    re.IGNORECASE,
)


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    # 1. Verify game & web 3D models exist and are non-empty glTF 2.0 binaries
    for name in REQUIRED_GAME_MODELS:
        p = ROOT / "game" / "assets" / "models" / name
        if not p.is_file() or p.stat().st_size < 1024:
            fail(f"Missing or empty game model: {p}")
        with p.open("rb") as fh:
            if fh.read(4) != b"glTF":
                fail(f"Invalid GLB magic header in {p}")

    for name in REQUIRED_WEB_MODELS:
        p = ROOT / "docs" / "models" / name
        if not p.is_file() or p.stat().st_size < 1024:
            fail(f"Missing or empty web model: {p}")
        with p.open("rb") as fh:
            if fh.read(4) != b"glTF":
                fail(f"Invalid GLB magic header in {p}")

    # 2. Verify SCORES.json parses cleanly
    scores = json.loads((ROOT / "game" / "assets" / "models" / "SCORES.json").read_text())
    if "models" not in scores or len(scores["models"]) < 11:
        fail("SCORES.json missing expected model entries")

    # 3. Verify docs/index.html structure, no inline style=, single <h1>, and all local refs exist
    html_path = ROOT / "docs" / "index.html"
    html = html_path.read_text(encoding="utf-8")
    if "style=" in html:
        fail("docs/index.html contains inline style= attribute")
    if len(re.findall(r"<h1\b", html)) != 1:
        fail("docs/index.html must have exactly one <h1>")
    for m in re.finditer(r'\b(?:src|href|poster)="([^"]+)"', html):
        ref = m.group(1)
        if ref.startswith(("http://", "https://", "#", "mailto:")):
            continue
        target = ROOT / "docs" / ref
        if not target.exists():
            fail(f"Broken local reference in docs/index.html: {ref}")

    # 4. Verify Markdown relative links in README.md, SPEC.md, ART_BIBLE.md
    for md_name in ("README.md", "SPEC.md", "ART_BIBLE.md", "CONTRIBUTING.md", "SECURITY.md"):
        md_path = ROOT / md_name
        text = md_path.read_text(encoding="utf-8")
        for m in re.finditer(r"\]\(([^)]+)\)", text):
            ref = m.group(1).split("#")[0].strip()
            if not ref or ref.startswith(("http://", "https://", "mailto:")):
                continue
            if not (ROOT / ref).exists():
                fail(f"Broken link in {md_name}: {ref}")
        for m in re.finditer(r'<img\s+[^>]*src="([^"]+)"', text):
            ref = m.group(1)
            if not ref.startswith(("http://", "https://")) and not (ROOT / ref).exists():
                fail(f"Broken <img> src in {md_name}: {ref}")

    # 5. Verify shell & sbatch syntax
    for sh in list((ROOT / "tools").glob("*.sh")) + list((ROOT / "cluster").glob("*.sbatch")):
        res = subprocess.run(["bash", "-n", str(sh)], capture_output=True, text=True)
        if res.returncode != 0:
            fail(f"Shell syntax error in {sh}: {res.stderr}")

    # 6. Privacy / internal path scan across all tracked text files
    self_rel = Path(__file__).relative_to(ROOT)
    tracked = subprocess.check_output(["git", "-C", str(ROOT), "ls-files"], text=True).splitlines()
    for rel in tracked:
        if Path(rel) == self_rel:
            continue
        fp = ROOT / rel
        if not fp.is_file() or fp.suffix.lower() in {".png", ".jpg", ".gif", ".mp3", ".mp4", ".glb", ".import", ".uid"}:
            continue
        txt = fp.read_text(encoding="utf-8", errors="ignore")
        hit = FORBIDDEN_PATTERNS.search(txt)
        if hit:
            fail(f"Forbidden internal/private string '{hit.group(0)}' in {rel}")

    print("VERIFY OK: models, docs, links, shell scripts, and privacy checks passed.")


if __name__ == "__main__":
    main()
