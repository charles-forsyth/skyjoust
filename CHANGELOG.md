# Changelog

All notable changes to **Skyjoust** are documented in this file.

## [1.0.0] - 2026-11-13

### Added
- Complete deterministic 60 Hz 2.5D aerial jousting arena in Godot 4.7 Forward+ (`game/main.gd`, `game/rider.gd`, `game/egg.gd`).
- Three playable modes: **Classic Arcade**, **Daily Seeded Challenge** (`YYYY-MM-DD`), and hazard-free **Peaceful Flight**.
- Upgraded octree-512 3D enemy rider models (`enemy_bounder`, `enemy_hunter`, `enemy_shadowlord`) from strict side-profile concepts (`9.0–9.5/10` QA scores).
- Two-segment hinged multi-feather wing rig (`wing_feathered.glb` via `tools/build_wing_mesh.py`) with downstroke extension and recovery wrist flexion.
- Player **Air-Dash Lunge** (`SHIFT` / `J` / Gamepad `X`/`RB`) with `+0.20` lance tie-break advantage and wave-final / pterodactyl slow-motion impact beat.
- Four dynamic arena themes cycling every 4 waves (*Sunset Isles*, *Moonlit Ruins*, *Storm Crags*, *Ember Peaks*) with custom FBM horizon-fog lava (`lava.gdshader`), basalt Lava Troll Hand (`magma_rock.gdshader`, Wave 3+), crumbling wrap ledges (Wave 6+), Pterodactyl beak-only hunter, and Shield / Long Lance power-ups.
- Deterministic zero-sample FFmpeg `lavfi` sound effects suite (`tools/make_sfx.sh`) and persistent `user://settings.cfg` audio/high-score state.
- 30-check headless verification suite (`test_all.gd`, `tests_hand.gd`, `tests_crumble.gd`), `SPEC.md`, `ART_BIBLE.md`, `tools/build_mac_app.sh`, and interactive WebGL 3D showcase (`docs/`).
