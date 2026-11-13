# Skyjoust Art Bible (v1.0 — Look B: Bright Stylized Sky Islands)

Chuck selected **Look B** on 2026-11-12 over Look A (dark photoreal) and Look C (synthwave neon). Every 2D backdrop, 3D Hunyuan model, procedural mesh, and shader in `Skyjoust` follows this specification.

## 1. Look in One Line
Warm, hand-painted tabletop miniatures dueling among carved terracotta sky islands suspended above a bubbling sea of dark-crusted molten magma.

## 2. Readability & Silhouette Rules (2.5D Side Camera)
- **Player vs Enemy Instant Contrast:**
  - **Player (`player_ostrich`):** Saturated cobalt-blue ostrich mount, bright silver-blue knight armour, soft additive blue backdrop halo (`QuadMesh`), and a `0.055` light-cyan inverted-hull outline (`Color(0.75, 0.92, 1.0)`).
  - **Enemies (`enemy_bounder`, `enemy_hunter`, `enemy_shadowlord`):** Warm crimson/brown, steel-grey, and obsidian-violet vultures with `0.040` near-black outlines (`Color(0.12, 0.03, 0.05)`).
- **Lances Must Read Horizontally:**
  - Because *Joust* is decided by lance-tip elevation (`lance_y = pos.y + 1.35`), every mounted knight concept MUST be prompted in **strict right-facing side profile** with the lance held **strictly horizontal above the bird's head** and clear empty background between lance shaft and neck, reconstructed at `HY_OCT=512` (`80,000` faces).
- **Matte Toy Finish over Raw AI Metallic:**
  - Hunyuan3D-2 exports GLBs with `metallic = 1.0`, which turns feathers black in shadow. `ModelFit.matte()` converts every surface to `metallic = 0.0`, `metallic_specular = 0.30`, `roughness = 0.75`, `rim_enabled = true` (`rim = 0.6, rim_tint = 0.4`).

## 3. Arena Palette Progression (4-Wave Cycle)
1. **Sunset Isles (Waves 1–4):** Peach/gold cumulus clouds, warm sunlight `(1.00, 0.86, 0.68)`, terracotta carved stone topped with lush green turf, red-orange magma fading into golden horizon haze `(1.00, 0.62, 0.36)`.
2. **Moonlit Ruins (Waves 5–8):** Deep indigo/violet starlight, cool lavender key `(0.75, 0.70, 1.00)`, higher ambient (`0.80`) so dark silhouettes pop, rose-magenta horizon haze.
3. **Storm Crags (Waves 9–12):** Slate thunderheads, crisp cyan-white key `(0.85, 0.95, 1.00)`, ambient `0.90`, violet-tinted magma seams.
4. **Ember Peaks (Waves 13–16):** Volcanic ash sky, fiery orange key `(1.00, 0.60, 0.40)`, glowing ember horizon `(0.90, 0.35, 0.15)`.

## 4. Lava & Shader Discipline
- **Never Caramel/Gold Lava:** Under ACES tonemapping (`exposure = 1.05, glow_hdr_threshold = 1.1`), bright yellow unshaded planes wash out into flat gold. `lava.gdshader` keeps **~70% dark cooled basalt crust** (`vec3(0.09, 0.025, 0.02)`) with saturated red-orange melt seams and zero `ALBEDO > 1.0` blowout, fading into `haze` over `32..62` view units and dissolving alpha over `55..70` units.
- **No Unintended Positive-Scale Flips:** Procedural meshes (`wing_feathered.glb`) author separate right/left geometry with positive scale and outward normals so `cull_front` outlines never invert.

## 5. Concept Prompt Rules
- **3D Props & Riders (`concepts/`):** Single subject, strict side-profile (for riders) or clean 3/4 view (for islands/egg/pad), wide margin on a flat neutral studio background, no capes/cloaks, folded mount wings, zero text labels.
- **2D Arena Backdrops (`game/assets/art/`):** `16:9`, painterly stylized clouds and distant tiny floating islands only; centre and lower half open sky/mist with **no foreground ground plane** so the 3D lava horizon blends seamlessly.
