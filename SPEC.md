# Skyjoust — Complete Technical & Design Specification (`SPEC.md`)

Version: 1.0.0 (As-Built & End-to-End Verified)
Date: 2026-11-13
Repository: `https://github.com/charles-forsyth/skyjoust`
Showcase & 3D Viewer: `https://charles-forsyth.github.io/skyjoust/`
Engine: Godot Engine 4.7.2 (`Forward+`, Apple Metal 4.0 / Vulkan, GDScript 2.0)

---

## 1. System Overview & End-to-End Architecture

Skyjoust is an independent modern 2.5D single-screen arcade tribute inspired by Williams Electronics' *Joust* (1982), built in **Look B** (bright hand-painted stylized 3D floating sky islands suspended above a molten volcanic sea). All AI asset generation executes strictly offline at build time across a local macOS workstation and a Slurm GPU cluster; the shipped game is 100% deterministic with zero runtime AI or network calls.

```text
[Offline Build-Time Asset Pipeline]
  Lumina (Gemini Image CLI)              FFmpeg lavfi + gen-music           Blender 5.2.3 (-b Python)
  - 4x 16:9 Arena Backdrops              - 11x Synthesized Arcade SFX       - tools/build_wing_mesh.py
  - Batch 1 Props & Player Concepts      - 20s Crossfaded Lava Ambience       (2-segment bmesh wings)
  - Batch 2 Strict Side-Profile Knights  - 60s Fantasy Loop (off by default) - tools/sides.py (4-yaw QA)
                 |                                      |                              |
                 v                                      |                              |
  [Slurm GPU Cluster: Hunyuan3D-2]                      |                              |
  - Batch 1 (NVIDIA L4, octree=384):                    |                              |
    8x props/mounts/player (60k faces)                  |                              |
  - Batch 2 (Tesla V100, octree=512):                   |                              |
    3x enemy knights x 2 seeds (80k faces,              |                              |
    s7 winners promoted: 9.0-9.5/10)                    |                              |
                 |                                      |                              |
                 +--------------------------------------+------------------------------+
                                                        |
                                                        v
                         [Godot 4.7.2 Forward+ Runtime: game/ (Zero Runtime AI)]
  +---------------------------------------------------------------------------------------------------+
  | Deterministic 2D Arena Plane (x in [-15, 15), wrap-safe maths, 60 Hz fixed tick, seeded `rng`)    |
  |   - main.gd: State/Mode machine, wave director, AI, joust collisions, hazards, HUD, --sim/--demo  |
  |   - rider.gd: Gravity/flap/drag/run integration, Air-Dash lunge, hinged wing & visual sync        |
  |   - egg.gd: Bounce/settle physics, underside ledge deflection, tier hatch countdown               |
  +---------------------------------------------------------------------------------------------------+
  | 3D Forward+ Presentation Layer (separate `vis_rng` so visuals never perturb gameplay determinism) |
  |   - model_fit.gd: AABB height normalization, metallic->matte conversion, inverted-hull outlines   |
  |   - shaders/: lava.gdshader (FBM + horizon fog), outline.gdshader, magma_rock.gdshader, shield    |
  |   - sfx.gd + pause_ctl.gd: 12-voice SFX pool, persistent user://settings.cfg, pause-safe input    |
  +---------------------------------------------------------------------------------------------------+
                                                        |
                                                        v
                         ~/Games/Skyjoust/Skyjoust.app (tools/build_mac_app.sh)
```

---

## 2. Core Architectural Decisions & Operational Rules

1. **Deterministic 2D Gameplay Plane Mirrored by 3D Nodes:**
   - Every gameplay entity (`Rider`, `Egg`, Pterodactyl, Power-Up, Lava Troll Hand) computes collisions and movement in pure 2D coordinates (`Vector2`, `x` right, `y` up) using explicit `Rect2` platform sweeps rather than 3D physics bodies. This prevents high-speed tunneling, guarantees exact toroidal wrap behavior at `x = +-15.0`, and enables 20 minutes of gameplay (`--sim=1200`) to be verified headlessly in ~4 seconds.
2. **RNG Isolation (`rng` vs `vis_rng`):**
   - `rng` drives enemy spawns, AI decisions, power-up drops, and hand break-free rolls.
   - `vis_rng` drives camera shake offsets. Calling or skipping `_update_visuals(dt)` never alters `rng` state (verified in regression check #9).
3. **Hybrid Sculpted Riders + Procedural Hinged Flight Wings:**
   - Monolithic image-to-3D mounts have folded wings so silhouettes reconstruct cleanly without thin-membrane tearing. Dynamic flapping is provided by attaching `wing_feathered.glb` (`WingRight`/`WingLeft` + `WristRight`/`WristLeft`) onto shoulder pivots (`rider.gd:_attach_flight_wings`), hidden while grounded so the sculpted folded wings show and articulated in flight.
4. **Side-Profile `octree=512` Rule for Jousting Knights:**
   - Front-angled 3/4 concepts foreshortened forward-pointing lances into stubby nubs (`3.0–4.5/10`). Re-generating from strict right-facing side-profile concepts with clear empty sky between the horizontal lance and the bird's head at `HY_OCT=512`, `HY_FACES=80000` on Tesla V100 GPUs raised enemy rider quality to **`9.0–9.5/10`** with uniform `MODEL_YAW = 0.0`.
5. **macOS Environment & Shutdown Hygiene:**
   - Launch scripts strip leaked Python 3.14 paths (`env -u PYTHONPATH` / `unset PYTHONPATH`).
   - Detached GLTF subtrees clear `owner = null` recursively (`ModelFit.detach`) before reparenting so Godot emits zero owner warnings.
   - Shaders are fetched via Godot's C++ `ResourceLoader` cache rather than GDScript `static var` references, and `Sfx` skips `AudioStreamPlayer.play()` under the `headless` dummy audio driver so headless tests exit with **0 leaked ObjectDB instances and 0 resources in use**.

---

## 3. Arena Topology, Camera & Coordinate System

### 3.1 World Bounds & Camera Framing
| Parameter | Value | Description |
|---|---:|---|
| `HALF` | `15.0` | Horizontal half-width; arena spans `x in [-15.0, 15.0)` (`30.0` units wide) and wraps seamlessly. |
| `LAVA_Y` | `-1.2` | Molten surface elevation; below `-1.2` triggers lava death (Classic/Daily) or thermal updraft (Peaceful). |
| `CEIL` | `16.4` | Invisible arena ceiling (`pos.y + H <= 16.4`; upward velocity clamped `<= -1.0` on contact). |
| `HAND_ZONE_Y` | `2.6` | Vertical danger zone over outer lava (`abs(x) > 9.4`, `y < 2.6`) for the Lava Troll Hand (Wave `3+`). |
| Camera | `FOV 50 deg` | `Camera3D` at `(0.0, 7.3, 30.8)` looking at `(0.0, 6.7, 0.0)`, `KEEP_WIDTH`, `1920x1080` virtual (`1600x900` window). |

Wrap-seam deltas always use `_wrap_dx(a, b)` (shortest signed path across `+-HALF`) and `_wrap_x(x)` so clashes, chases, and particles near `x = +-14.8` never jump across `x = 0`.

### 3.2 Platform Layout (`PLATS` in `game/main.gd`)
| Index | Role | `Rect2(x, y, w, h)` | Top `y` | Model | Crumble (`Wave 6+`) |
|---:|---|---|---:|---|---|
| `0` | Central base bridge | `(-9.0, -0.4, 18.0, 1.6)` | `1.2` | `platform_base.glb` | Never |
| `1` | Lower-left wrap ledge | `(-15.0, 4.6, 4.6, 0.7)` | `5.3` | `platform_short.glb` | Yes (`CRUMBLE`) |
| `2` | Lower-right wrap ledge | `(10.4, 4.6, 4.6, 0.7)` | `5.3` | `platform_short.glb` | Yes (`CRUMBLE`) |
| `3` | Centre island | `(-4.0, 6.2, 7.5, 0.7)` | `6.9` | `platform_long.glb` | Never |
| `4` | Upper-left island | `(-11.5, 9.4, 5.5, 0.7)` | `10.1` | `platform_long.glb` | Never |
| `5` | Upper-right island | `(6.0, 8.9, 6.0, 0.7)` | `9.6` | `platform_long.glb` | Never |
| `6` | Top-left wrap ledge | `(-15.0, 12.4, 3.4, 0.7)` | `13.1` | `platform_short.glb` | Yes (`CRUMBLE`) |
| `7` | Top-right wrap ledge | `(11.6, 12.4, 3.4, 0.7)` | `13.1` | `platform_short.glb` | Yes (`CRUMBLE`) |
| `8` | Top-centre island | `(-2.0, 12.6, 5.0, 0.7)` | `13.3` | `platform_short.glb` | Never |

Odd-indexed elevated ledges rotate `PI` radians around `Y` and vary vertical thickness (`1.0 + 0.12 * (idx % 3)`) so adjacent islands expose varied stone carvings.

### 3.3 Spawn Pads (`SPAWNS`)
Five glowing rune pads (`spawn_pad.glb`) sit flush on platforms at `(-5.5, 1.2)`, `(5.5, 1.2)`, `(-0.3, 6.9)`, `(-8.7, 10.1)`, and `(9.0, 9.6)`. Player spawns at `(0.0, 1.2)` (`spawn_t = 1.0s`, `invuln = 2.5s`); enemies pick the pad maximizing `distance_to(player.pos) + randf() * 4.0` (`spawn_t = 1.2s`).

---

## 4. Rider Physics, Air-Dash & Combat Rules (`game/rider.gd`, `game/main.gd`)

### 4.1 Movement & Flight Physics Constants
| Constant | Value | Mechanics |
|---|---:|---|
| `W`, `H` | `1.1`, `1.7` | Rider AABB width and height (feet at `pos`, head at `pos.y + 1.7`). |
| `LANCE` | `1.35` | Lance tip elevation above `pos.y` (`lance_y() = pos.y + 1.35`). |
| `G` | `24.0` | Downward gravity (`u/s^2`), reduced to `0.25 * G` (`6.0`) while Air-Dashing. |
| `FLAP` | `7.6` | Upward velocity impulse per flap (`vel.y = clamp(vel.y + 7.6, 4.18, 9.0)`), `flap_cd = 0.11s`. |
| `VY_MAX`, `FALL_MAX` | `9.0`, `-14.0` | Vertical climb cap and terminal fall speed. |
| `GROUND_ACC`, `GROUND_FRIC` | `20.0`, `14.0` | Horizontal ground acceleration and stopping friction. |
| `AIR_ACC`, `AIR_DRAG` | `7.0`, `0.8` | Horizontal air steering acceleration (`+1.2` horizontal kick on directional flap) and glide drag. |
| `DASH_V` | `15.5` | Player Air-Dash horizontal surge speed (`vel.x = facing * 15.5`, `vel.y = max(vel.y, 0.8)`). |
| `DASH_DUR`, `DASH_CD` | `0.18s`, `2.2s` | Air-Dash active window and cooldown timer. |

### 4.2 Rider Classes & AI Profiles
| `Rider.Kind` | Mount / Armour | Base `max_vx` | Base `ai_flap_cd` | Kill Score | Egg Tier | AI Flight Behaviour |
|---|---|---:|---:|---:|---:|---|
| `PLAYER` | Blue Ostrich / Silver-Blue Knight | `9.0` | Player input | — | — | Player controlled (or `_autopilot()` in `--demo` / `--sim`). |
| `BOUNDER` | Red-Brown Vulture / Crimson Knight | `5.0` | `0.26s` | `500` | `0` (`7.0s` hatch) | Patrols random altitudes (`3.5..13.0`), reverses direction `25%` per AI tick. |
| `HUNTER` | Slate-Grey Vulture / Steel Knight | `7.0` | `0.18s` | `750` | `1` (`6.0s` hatch) | Tracks toward `player.pos.x` (wrap-aware) at `player.pos.y + 0.5..3.0`. |
| `SHADOW` | Dark Violet Vulture / Obsidian Knight | `8.5` | `0.13s` | `1,500` | `2` (`5.0s` hatch) | Aggressively hunts `player.pos.y + 1.6`; climbs `+2.5` whenever within `4.0` horizontal units of a level/higher player. |

Wave scaling (`_apply_wave_scaling`): enemy `max_vx` scales by `1.0 + min(0.04 * (wave - 1), 0.40)` and `ai_flap_cd` tightens by `max(1.0 - 0.03 * (wave - 1), 0.70)`.

### 4.3 Joust Collision & Impact Juice
Two active riders overlap when `abs(_wrap_dx(a.pos.x, b.pos.x)) < W * 0.95` (`1.045`) and `abs(a.pos.y - b.pos.y) < H * 0.85` (`1.445`). Effective lance height differential for the player is:

```text
diff = player.lance_y() - enemy.lance_y()
     + (0.50 if long_lance > 0.0 else 0.0)
     + (0.20 if player.dashing() else 0.0)
```

- **`diff > +0.22` (`JOUST_MARGIN`) — Player Wins:** Enemy is unmounted (`KILL_SCORE` awarded, egg popped at `(0.5 * vx, +3.0)`, riderless buzzard flees off-screen at `vx = +-11.5`, `14%` power-up roll, feather + spark burst, `hitstop = 0.07s`, upward player rebound `vel.y >= 3.0`). If this slays the final enemy of the wave (`enemies.is_empty() and pending_spawns.is_empty()`), triggers **`slowmo_t = 0.22s`** (`0.32x` simulation/visual rate).
- **`diff < -0.22` — Enemy Wins:**
  - If `player.invuln > 0.0`: ignored (spawn/recovery grace).
  - Else if `shield > 0.0`: consumes `SHIELD`, bounces riders apart, grants `player.invuln = 1.2s`, flashes `"SHIELD BROKEN"`.
  - Else: `_player_dies("lance")` (`lives -= 1`, `hitstop = 0.12s`, `shake = 0.5`, `1.6s` respawn delay).
- **`abs(diff) <= 0.22` — Clash Tie:** `_bounce(player, enemy)` separates horizontal velocities (`>= 6.0 u/s`), adds `+2.0` vertical lift, sets `bounce_cd = 0.25s`, plays `clash.mp3`, and spawns a shockwave ring at the wrap-safe seam midpoint.

---

## 5. Game Modes, Wave Progression, Hazards & Power-Ups

### 5.1 Three Playable Modes (`Main.Mode`)
| Mode | Trigger (Title / Game Over) | Rules & Persistence |
|---|---|---|
| **Classic Arcade** (`Mode.CLASSIC`) | `SPACE` / `ENTER` / Gamepad `A` | Random `rng` per run (`seed = 1982` in `--demo`/`--sim`), `5` starting lives, extra life every `20,000` pts, full wave progression, hazards, and power-ups. Saves `[score] best`. |
| **Daily Challenge** (`Mode.DAILY`) | `C` | Deterministic `rng.seed = YYYY * 10000 + MM * 100 + DD` derived from system clock (`_daily_info()`). Identical enemy spawns and drops all day. HUD displays `DAILY YYYY-MM-DD  WAVE N` and `DAILY BEST`. Saves `[daily] date` and `[daily] best`. |
| **Peaceful Flight** (`Mode.PEACEFUL`) | `F` | Relaxed hazard-free exploration & egg gathering: `0` enemy spawns, no pterodactyl or lava hand, eggs never hatch into enemies (`5` golden eggs kept active across ledges at all times), touching `LAVA_Y` gently launches the player upward (`vel.y = 10.5`) with golden sparkles instead of losing a life, and every `10` eggs collected cycles smoothly to the next painted sky-island arena. |

### 5.2 Wave Structure & Arena Theme Rotation
- Standard waves spawn `min(3 + wave, 9)` enemy riders (`0.8s` initial delay, `1.1s` interval). Waves `1–2` are Bounders; Wave `3+` mixes Hunters (`p = 0.15 + 0.05 * wave`); Wave `5+` mixes Shadowlords (`p = 0.06 * (wave - 3)`).
- Clearing a wave with zero player deaths awards **`+3,000` SURVIVAL BONUS**.
- **Egg Waves (`wave % 5 == 0`):** Restores any crumbled ledges, suppresses initial rider spawns, and places `8` golden eggs across elevated islands—collect them quickly before they hatch into Hunters!
- **Arena Themes (`((wave - 1) / 4) % 4`):** Cycles every 4 waves across four Lumina-painted backdrops and lighting/shader palettes:

| Index | Theme Name | Backdrop | Sun Color | Ambient (`energy`) | Lava `haze` / `tint` |
|---:|---|---|---|---|---|
| `0` | `SUNSET ISLES` | `backdrop.png` | `(1.00, 0.86, 0.68)` | `(0.85, 0.78, 0.90)` (`0.55`) | `(1.00, 0.62, 0.36)` / `(1.00, 1.00, 1.00)` |
| `1` | `MOONLIT RUINS` | `backdrop_dusk.png` | `(0.75, 0.70, 1.00)` | `(0.70, 0.60, 0.95)` (`0.80`) | `(0.75, 0.35, 0.55)` / `(1.00, 0.70, 0.90)` |
| `2` | `STORM CRAGS` | `backdrop_storm.png` | `(0.85, 0.95, 1.00)` | `(0.70, 0.85, 0.95)` (`0.90`) | `(0.42, 0.50, 0.55)` / `(0.75, 0.60, 1.00)` |
| `3` | `EMBER PEAKS` | `backdrop_ember.png` | `(1.00, 0.60, 0.40)` | `(0.90, 0.55, 0.45)` (`0.60`) | `(0.90, 0.35, 0.15)` / `(1.10, 0.90, 0.80)` |

### 5.3 Hazards & Pickups
1. **Golden Eggs (`game/egg.gd`):** Gravity `22.0`, radius `0.38`, height `0.76`, bounces off both platform tops (`0.3x` restitution) and platform undersides (`0.35x` restitution). Wobbles during the final `2.0s` before hatching (`7s / 6s / 5s` by tier) into a `HUNTER` (tier `0`) or `SHADOW` (tiers `1–2`). Collecting eggs awards streak points (`250 -> 500 -> 750 -> 1,000`, reset per wave) plus **`+500` `CATCH!`** when snatched in mid-air.
2. **Pterodactyl (`_ptero_tick`):** Arrives at `wave_t > 40.0s` (`PTERO_AFTER`) with `screech.mp3`, cruising horizontally at `10.5 u/s` while tracking `player.lance_y()`. Invulnerable to body/top strikes—only a head-on lance directly into its open beak (`facing_it` and `abs(ptero.y - player.lance_y()) < 0.50`, or `0.65` with Long Lance) slays it (`+1,000` pts, `hitstop = 0.15s`, `slowmo_t = 0.22s`, `25.0s` cooldown before another can appear).
3. **Lava Troll Hand (`_hand_tick`, Wave `3+`):** Articulated basalt forearm + palm + 4 two-knuckle fingers (`magma_rock.gdshader`). Targets any rider in `abs(x) > 9.4, y < 2.6`, rises from magma with splash particles, latches when the rider enters its palm box, and drags downward (`-9.0 * dt`). Each flap while gripped has an `18%` chance to break free (`3.0s` hand cooldown).
4. **Crumbling Ledges (`_crumble_tick`, Wave `6+`):** Outer wrap ledges `[1, 2, 6, 7]` accumulate stand time when any grounded rider stands on them, vibrate after `0.26s`, collapse into the magma at `1.3s`, and regrow `7.0s` later with a `Tween.TRANS_BACK` pop-in.
5. **Power-Ups (`_drop_power`, `_power_tick`):** `14%` drop rate on rider kills (`9.0s` lifetime, blinking after `6.5s`):
   - **`SHIELD`:** Cyan fresnel sphere (`shaders/shield.gdshader`); lasts until hit and absorbs one losing lance collision or off-axis pterodactyl hit.
   - **`LONG LANCE`:** `12.0s` forward golden energy spearhead; grants `+0.50` effective lance height and widens pterodactyl beak reach (`2.1` horizontal, `0.65` vertical).

---

## 6. 3D Asset Inventory, Hinged Wing Rig & Shaders

### 6.1 Verified 3D Models (`game/assets/models/`, `SCORES.json`)
| File | Size | Vertices | Triangles | Source / Batch | Octree | `MODEL_YAW` | QA Score |
|---|---:|---:|---:|---|---:|---:|---:|
| `enemy_hunter.glb` | `5.19 MB` | `50,401` | `80,000` | Hunyuan3D-2 V100 (`v2_s7`) | `512` | `0.0` | `9.5 / 10` |
| `enemy_bounder.glb` | `5.35 MB` | `52,553` | `80,000` | Hunyuan3D-2 V100 (`v2_s7`) | `512` | `0.0` | `9.0 / 10` |
| `enemy_shadowlord.glb` | `4.87 MB` | `49,806` | `80,000` | Hunyuan3D-2 V100 (`v2_s7`) | `512` | `0.0` | `9.0 / 10` |
| `egg.glb` | `2.80 MB` | `30,969` | `60,000` | Hunyuan3D-2 L4 (`batch1_s7`) | `384` | `0.0` | `9.0 / 10` |
| `spawn_pad.glb` | `3.63 MB` | `31,258` | `60,000` | Hunyuan3D-2 L4 (`batch1_s7`) | `384` | `0.0` | `9.0 / 10` |
| `player_ostrich.glb` | `4.72 MB` | `38,239` | `60,000` | Hunyuan3D-2 L4 (`batch1_s7`) | `384` | `0.0` | `8.0 / 10` |
| `platform_long.glb` | `4.50 MB` | `38,067` | `60,000` | Hunyuan3D-2 L4 (`batch1_s7`) | `384` | `0.0 / PI` | `8.0 / 10` |
| `platform_short.glb` | `4.38 MB` | `38,249` | `60,000` | Hunyuan3D-2 L4 (`batch1_s7`) | `384` | `0.0 / PI` | `8.0 / 10` |
| `buzzard_riderless.glb` | `4.43 MB` | `36,149` | `60,000` | Hunyuan3D-2 L4 (`batch1_s7`) | `384` | `PI * 0.5` | `7.0 / 10` |
| `pterodactyl.glb` | `3.97 MB` | `34,540` | `60,000` | Hunyuan3D-2 L4 (`batch1_s7`) | `384` | `PI * 0.5` | `7.0 / 10` |
| `platform_base.glb` | `4.97 MB` | `37,834` | `60,000` | Hunyuan3D-2 L4 (`batch1_s7`) | `384` | `0.0` | `6.5 / 10` |
| `wing_feathered.glb` | `0.04 MB` | `1,120` | `2,160` | Blender 5.2 (`tools/build_wing_mesh.py`) | BMesh | `0.0` | Procedural |

### 6.2 Hinged Multi-Feather Wing Rig (`tools/build_wing_mesh.py`)
- Authors `WingRight` (`+Z`) and `WingLeft` (`-Z`) explicitly with outward-recalculated normals (avoiding negative `Z` mirroring in Godot, which flips face winding and breaks `cull_front` outlines).
- Each wing has an `InnerArm` covert loft + `4` overlapping secondary feathers on the shoulder root, plus a `WristRight`/`WristLeft` hinge at `+-0.46 m` carrying `5` fanned primary feathers (`Primary_0..2` use `WingTip` lightened tint; inner feathers use species `WING_COLORS[kind]`).
- In flight, shoulder angle `wa = 0.35 + 1.25 * sin(flap_anim * PI) + (0.35 if vel.y < -2.0 else 0.0)` while wrist angle extends rigid (`+0.18 rad`) during active downstroke (`flap_anim > 0.35`) and flexes inward (`-0.42 rad`) on recovery/glide.

### 6.3 Custom Shaders (`game/shaders/`)
- **`lava.gdshader`:** Unshaded dual-FBM cooled basalt crust (`plates = smoothstep(0.40, 0.52, n)`) drifting over red-orange magma seams with vertex wave undulation (`+-0.12`), fading smoothly into `haze` over view distance `32..62` and alpha-dissolving over `55..70` so no hard geometry edge crosses the painted sky backdrop.
- **`outline.gdshader`:** Front-face culled (`cull_front`) inverted-hull `next_pass` extruding `VERTEX += NORMAL * width` (`0.055` light-blue on player; `0.04` dark crimson-black on enemies; `0.025` on wings/eggs/pterodactyl).
- **`magma_rock.gdshader`:** 3D value-noise dark basalt (`ROUGHNESS = 0.9`) with glowing orange-red fissure emission (`3.5x`) and molten wrist glow near `lp.y < 0.2`.
- **`shield.gdshader`:** Unshaded additive (`blend_add, depth_draw_never`) cyan fresnel bubble (`pow(1 - |N.V|, 2.2)`) with vertical sine pulse.

---

## 7. Audio System & Persistence Schema (`game/sfx.gd`, `tools/make_sfx.sh`)

### 7.1 Synthesized SFX & Music Inventory
All 11 sound effects + 20 s lava ambience are synthesized deterministically from `ffmpeg` `lavfi` expressions in `tools/make_sfx.sh` (zero external sample dependencies); `theme.mp3` was generated offline via `gen-music` and crossfade-looped:

| Asset | Duration | Size | Bus Gain (`VOL`) | Synthesis / Role |
|---|---:|---:|---:|---|
| `sfx/flap.mp3` | `0.22s` | `3.4 KB` | `-14.0 dB` | Bandpassed pink-noise wing whoosh (`+-12%` pitch jitter). |
| `sfx/dash.mp3` | `0.26s` | `2.8 KB` | `-6.0 dB` | Bandpassed white-noise air burst + upward `320->1420 Hz` harmonic sweep. |
| `sfx/clash.mp3` | `0.35s` | `3.7 KB` | `-6.0 dB` | Inharmonic metallic lance ring (`880 / 1390 / 2130 Hz` exponential decay). |
| `sfx/kill.mp3` | `0.50s` | `3.4 KB` | `-4.0 dB` | Low punch sweep + crisp impact transient. |
| `sfx/egg.mp3` | `0.40s` | `3.2 KB` | `-6.0 dB` | Two-note bright pickup chime (pitch rises `+3%` per `egg_streak`). |
| `sfx/hatch.mp3` | `0.43s` | `3.3 KB` | `-6.0 dB` | Shell crack + rising warning chirp. |
| `sfx/death.mp3` | `0.90s` | `6.8 KB` | `-3.0 dB` | Descending lance-defeat sweep. |
| `sfx/sizzle.mp3` | `0.70s` | `13.9 KB` | `-6.0 dB` | Filtered noise steam hiss on lava contact or hand emergence. |
| `sfx/screech.mp3` | `0.80s` | `14.7 KB` | `-4.0 dB` | FM-modulated pterodactyl cry. |
| `sfx/wave.mp3` | `0.90s` | `5.4 KB` | `-8.0 dB` | Brass-like wave fanfare chord. |
| `sfx/life.mp3` | `0.60s` | `5.6 KB` | `-6.0 dB` | Ascending arpeggio for Extra Life and Power-Up pickup. |
| `sfx/ambience.mp3` | `20.00s` | `133.9 KB` | `-16.0 dB` | Low-passed brown-noise volcanic rumble joined via `2.0s` `acrossfade` (zero loop dropout). |
| `music/theme.mp3` | `60.00s` | `1.33 MB` | `-12.0 dB` | Looped orchestral-fantasy theme; **OFF by default**, instantiated only when `M` is toggled on. |

### 7.2 Save File Schema (`user://settings.cfg`)
Shared cleanly between `Main` and `Sfx` (every write calls `cfg.load("user://settings.cfg")` first so audio toggles never clobber high scores):

```ini
[audio]
music=false
muted=false

[score]
best=42420

[daily]
date="2026-11-13"
best=18500
```

---

## 8. Controls, CLI Harness & Automated Verification Suite

### 8.1 Controls (`game/project.godot`, `game/pause_ctl.gd`, `game/main.gd`)
| Action | Keyboard | Gamepad | Notes |
|---|---|---|---|
| Steer / Run | `A` / `D`, `Left` / `Right` | Left Stick X (`> 0.3`) / D-Pad | Sets `facing` and ground/air acceleration. |
| Flap | `SPACE`, `W`, `Up` | South Button (`A` / Cross, idx `0`) | Also starts Classic Arcade on Title / Game Over. |
| Air-Dash | `SHIFT`, `J` | West Button (`X`, idx `2`) / `RB` (`10`) | `0.18s` horizontal surge, `2.2s` cooldown, `+0.20` tie-break. |
| Daily Challenge | `C` | — | Starts `Mode.DAILY` from Title or Game Over. |
| Peaceful Flight | `F` | — | Starts `Mode.PEACEFUL` from Title or Game Over. |
| Pause / Resume | `ESC`, `P` | — | Freezes `Main` (`PROCESS_MODE_PAUSABLE`) via `pause_ctl.gd` (`PROCESS_MODE_ALWAYS`). |
| Quit to Title | `Q` *(while paused)* | — | Unpauses, cleans arena entities, and restores Title menu. |
| Help & Rules Card | `H`, `F1` | — | Toggles opaque centered two-column Controls & Rules overlay. |
| Music / Mute | `M` / `N` | — | Toggles music (`off` default) / master bus mute; persists to `user://settings.cfg`. |

### 8.2 CLI Flags, Env Vars & Packaging Scripts
- **Interactive macOS Launch:** `./tools/build_mac_app.sh && open ~/Games/Skyjoust/Skyjoust.app` (builds & ad-hoc signs a native `.app` bundle with custom `AppIcon.icns`).
- **Autopilot Demo / Movie Capture:** `env -u PYTHONPATH caffeinate -d -u godot --path game --write-movie out.avi --fixed-fps 60 --quit-after 480 -- --demo`
  - Optional env vars: `SJ_START_WAVE=N` (jump directly to wave `N`), `SJ_POWER=1` (spawn both pickups), `SJ_AUDIO=1` (enable audio during `--demo`), `SJ_DEBUG=1` (60-frame state telemetry).
- **Headless Endurance Playtest:** `env -u PYTHONPATH godot --headless --path game -- --sim=1200` (simulates 20 minutes of 60 Hz gameplay in ~4 s).

### 8.3 Automated Regression Suite (`game/tests/`)
All 30 automated checks across 3 headless scripts pass with **0 warnings, 0 errors, and 0 leaked resources**:
- `env -u PYTHONPATH godot --headless --path game -s res://tests/test_all.gd` (**28/28 PASS**):
  1. `Sfx._save()` preserves `[score] best` across mute/music toggles.
  2–5. Pterodactyl spawns after `PTERO_AFTER`, `SHIELD` absorbs non-beak strikes, beak-height lance slays pterodactyl, and `25s` cooldown blocks next-frame respawn.
  6–7. `_start_game()` clears power-ups, restores crumbled ledges, resets `_died_this_wave`, and awards `3,000` Wave 1 Survival Bonus.
  8. Screen-wrap clash midpoint stays at screen seam (`|x| > 14.5`).
  9. Upward-popped egg bounces off ledge underside without tunneling through.
  10–11. Lava Troll Hand grabs low-skimming rider into magma; `ModelFit.outline` attaches `next_pass` onto `material_override` meshes.
  12. Crumbling edge ledge collapses after `1.3s` standing and regrows after `7.0s`.
  13–14. Player visual attachments (`ShaderMaterial` shield bubble, Long Lance beam, 2 flight wings).
  15. Seeded gameplay determinism is identical with or without `_update_visuals(dt)`.
  16–17. Hinged `WristRight`/`WristLeft` load from `wing_feathered.glb`, extending on downstroke (`> 0`) and flexing on recovery (`< 0`).
  18–20. Air-Dash surges at `DASH_V` (`15.5`), enforces cooldown, slays a near-level rival via `+0.20` tie-break, and triggers `slowmo_t` on wave-final kill.
  21. Daily Challenge (`Mode.DAILY`) produces identical `pending_spawns` across runs.
  22–25. Peaceful Flight (`Mode.PEACEFUL`) starts with `5` golden eggs and `0` enemies, never hatches enemies, updrafts out of lava (`vel.y > 9.0`) without losing lives, and cycles arena themes every `10` eggs.
  26–28. Help card toggles cleanly, Pause freezes `SceneTree`, and Quit-to-Title unpauses and cleans all arena entities.
- `env -u PYTHONPATH godot --headless --path game -s res://tests/tests_hand.gd` (**PASS**).
- `env -u PYTHONPATH godot --headless --path game -s res://tests/tests_crumble.gd` (**PASS**).
