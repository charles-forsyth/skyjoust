(function () {
  "use strict";

  const MODELS = [
    {
      id: "player_ostrich",
      label: "Player — Ostrich Knight",
      sub: "Blue Mount · Score 8.0/10",
      role: "Player Avatar (max_vx 9.0, Dash 15.5)",
      octree: "384 (24k web / 60k game)",
      score: "8.0 / 10",
      desc: "Cobalt-blue ostrich mount with striped horizontal lance. In-game, paired with a cyan halo, fresnel energy shield, and hinged feathered flight wings."
    },
    {
      id: "enemy_hunter",
      label: "Hunter — Steel Buzzard",
      sub: "Octree 512 · Score 9.5/10",
      role: "Wave 3+ Pursuer (750 pts)",
      octree: "512 (26k web / 80k game)",
      score: "9.5 / 10",
      desc: "Silver-armoured knight with gold crest and full-length horizontal lance. Actively tracks toward the player's horizontal wrap position and climbs above lance height."
    },
    {
      id: "enemy_bounder",
      label: "Bounder — Crimson Buzzard",
      sub: "Octree 512 · Score 9.0/10",
      role: "Wave 1+ Patrol (500 pts)",
      octree: "512 (26k web / 80k game)",
      score: "9.0 / 10",
      desc: "Red-plumed knight atop a brown vulture with separated S-curved neck and red/white striped tournament lance."
    },
    {
      id: "enemy_shadowlord",
      label: "Shadowlord — Obsidian",
      sub: "Octree 512 · Score 9.0/10",
      role: "Wave 5+ Elite (1,500 pts)",
      octree: "512 (26k web / 80k game)",
      score: "9.0 / 10",
      desc: "Fastest enemy rider (max_vx 8.5, flap cadence 0.13 s). Climbs aggressively whenever the player closes within 4 units at level altitude."
    },
    {
      id: "pterodactyl",
      label: "Pterodactyl Hunter",
      sub: "Apex Hazard · 1,000 pts",
      role: "40s Wave Timer Hazard",
      octree: "384 (22k web / 60k game)",
      score: "7.0 / 10",
      desc: "Swoops in at 40 seconds into a drawn-out wave. Immune to body strikes — only a head-on lance straight into its open beak slays it."
    },
    {
      id: "wing_feathered",
      label: "Hinged Feathered Wings",
      sub: "Blender BMesh · 2,160 tris",
      role: "Procedural 2-Segment Flight Rig",
      octree: "BMesh Loft (9 feathers/side)",
      score: "Procedural",
      desc: "Custom left/right shoulder + wrist-hinged primary and secondary feathers with outward-facing normals. Extends rigid on downstroke and flexes inward on recovery."
    },
    {
      id: "egg",
      label: "Golden Buzzard Egg",
      sub: "Octree 384 · Score 9.0/10",
      role: "250-1,000 Streak (+500 Catch!)",
      octree: "384 (16k web / 60k game)",
      score: "9.0 / 10",
      desc: "Bouncing speckled egg dropped by unmounted riders. Wobbles during the final 2 seconds before hatching into a tougher Hunter or Shadowlord."
    },
    {
      id: "buzzard_riderless",
      label: "Fleeing Buzzard Mount",
      sub: "Octree 384 · Score 7.0/10",
      role: "Unmounted Visual Escape",
      octree: "384 (22k web / 60k game)",
      score: "7.0 / 10",
      desc: "When an enemy knight is unmounted, their riderless vulture bolts off-screen with flapping feathered wings while the egg arcs toward a ledge."
    },
    {
      id: "platform_long",
      label: "Carved Sky Island",
      sub: "Octree 384 · Score 8.0/10",
      role: "Elevated Arena Ledge",
      octree: "384 (22k web / 60k game)",
      score: "8.0 / 10",
      desc: "Hand-painted terracotta masonry topped with green turf and tiny flora. Odd-indexed ledges mirror 180 deg around Y to break visual repetition."
    },
    {
      id: "spawn_pad",
      label: "Rune Spawn Pad",
      sub: "Octree 384 · Score 9.0/10",
      role: "5 Arena Materialisation Pads",
      octree: "384 (18k web / 60k game)",
      score: "9.0 / 10",
      desc: "Glowing carved stone pads anchored on the base bridge and elevated islands where knights materialise with brief spawn invulnerability."
    }
  ];

  const ARENAS = [
    {
      name: "Sunset Isles",
      waves: "Waves 1 - 4 (and Peaceful Flight start)",
      img: "assets/shot_combat.jpg",
      desc: "Warm golden-hour cumulus clouds and waterfalls framing terracotta ruins over dark-crusted red magma. Showcases Daily Challenge mode with Shield and Long Lance active.",
      sun: "#ffdbad",
      amb: "#d9c7e6",
      haze: "#ff9e5c"
    },
    {
      name: "Moonlit Ruins",
      waves: "Waves 5 - 8 (and Peaceful Sky Tour)",
      img: "assets/shot_peaceful.jpg",
      desc: "Cosmic indigo twilight with boosted cool-lavender ambient fill (0.80) so dark rider silhouettes stay crisp, paired with rose-tinted volcanic mist.",
      sun: "#bfb3ff",
      amb: "#b399f2",
      haze: "#bf598c"
    },
    {
      name: "Storm Crags",
      waves: "Waves 9 - 12 (Crumbling Ledges + Hand Active)",
      img: "assets/shot_storm.jpg",
      desc: "High-altitude slate thunderheads lit by crisp cyan-white key lighting and violet-shifted magma seams while outer wrap ledges shake and collapse under weight.",
      sun: "#d9f2ff",
      amb: "#b3d9f2",
      haze: "#6b808c"
    },
    {
      name: "Ember Peaks",
      waves: "Waves 13 - 16 (High-Speed Shadowlord Waves)",
      img: "assets/shot_ember.jpg",
      desc: "Volcanic ash clouds and intense orange-red bounce light over superheated fissures as wave speed scaling reaches +40%.",
      sun: "#ff9966",
      amb: "#e68c73",
      haze: "#e65926"
    }
  ];

  const SFX_LIST = [
    { id: "flap", name: "Wing Flap", meta: "0.22s · pink noise", recipe: 'anoisesrc=d=0.22:c=pink -> highpass=300,lowpass=2200' },
    { id: "dash", name: "Air-Dash Lunge", meta: "0.26s · sweep + burst", recipe: 'bandpass=1400 + sin(2*PI*(320+1100*t)*t)*exp(-7*t)' },
    { id: "clash", name: "Lance Clash", meta: "0.35s · metallic ring", recipe: 'inharmonic sines 880 / 1390 / 2130 Hz * exp(-10*t)' },
    { id: "kill", name: "Unmount Kill", meta: "0.50s · impact thump", recipe: 'low frequency pitch drop + transient snap' },
    { id: "egg", name: "Golden Egg", meta: "0.40s · streak chime", recipe: 'two-step harmonic bell (+3% pitch per egg_streak)' },
    { id: "hatch", name: "Shell Hatch", meta: "0.43s · warning chirp", recipe: 'chirp sweep alerting Hunter/Shadowlord emergence' },
    { id: "screech", name: "Pterodactyl", meta: "0.80s · FM cry", recipe: 'FM-modulated high carrier screech at wave_t = 40s' },
    { id: "sizzle", name: "Lava Sizzle", meta: "0.70s · steam hiss", recipe: 'filtered white noise burst on magma contact' },
    { id: "life", name: "Power / 1-UP", meta: "0.60s · arpeggio", recipe: 'ascending triad chime on Shield / Long Lance / 20k' },
    { id: "wave", name: "Wave Clear", meta: "0.90s · brass chord", recipe: 'warm multi-harmonic fanfare on wave start' }
  ];

  // Video play/pause button
  const heroVideo = document.getElementById("hero-video");
  const btnVideo = document.getElementById("btn-video");
  if (heroVideo && btnVideo) {
    btnVideo.addEventListener("click", function () {
      if (heroVideo.paused) {
        heroVideo.play();
        btnVideo.textContent = "Pause Clip";
      } else {
        heroVideo.pause();
        btnVideo.textContent = "Play Clip";
      }
    });
  }

  // 3D Model Viewer Hangar
  const mv = document.getElementById("mv");
  const tabsEl = document.getElementById("model-tabs");
  const titleEl = document.getElementById("insp-title");
  const descEl = document.getElementById("insp-desc");
  const roleEl = document.getElementById("insp-role");
  const octEl = document.getElementById("insp-oct");
  const scoreEl = document.getElementById("insp-score");
  const dimEl = document.getElementById("insp-dim");
  const badgeEl = document.getElementById("viewer-badge");
  const viewerCard = document.getElementById("viewer-card");

  function selectModel(m) {
    document.querySelectorAll(".model-tab").forEach(function (b) {
      b.classList.toggle("active", b.dataset.id === m.id);
    });
    titleEl.textContent = m.label;
    descEl.textContent = m.desc;
    roleEl.textContent = m.role;
    octEl.textContent = m.octree;
    scoreEl.textContent = m.score;
    dimEl.textContent = "Measuring...";
    badgeEl.textContent = "models/" + m.id + ".glb";
    if (mv) {
      mv.setAttribute("src", "models/" + m.id + ".glb");
    }
  }

  function updateDims() {
    if (!mv || typeof mv.getDimensions !== "function") return;
    try {
      const d = mv.getDimensions();
      if (d && (d.x > 0 || d.y > 0 || d.z > 0)) {
        dimEl.textContent = d.x.toFixed(2) + " x " + d.y.toFixed(2) + " x " + d.z.toFixed(2) + " m";
        mv.dataset.loaded = "1";
      }
    } catch (_) {}
  }

  if (tabsEl) {
    MODELS.forEach(function (m) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "model-tab";
      btn.dataset.id = m.id;
      const strong = document.createElement("span");
      strong.textContent = m.label;
      const small = document.createElement("small");
      small.textContent = m.sub;
      btn.appendChild(strong);
      btn.appendChild(small);
      btn.addEventListener("click", function () {
        selectModel(m);
      });
      tabsEl.appendChild(btn);
    });
    selectModel(MODELS[0]);
  }

  if (mv) {
    mv.addEventListener("load", updateDims);
    if (window.customElements && customElements.whenDefined) {
      customElements.whenDefined("model-viewer").then(updateDims);
    }
  }

  const btnRot = document.getElementById("btn-rot");
  if (btnRot && mv) {
    btnRot.addEventListener("click", function () {
      mv.autoRotate = !mv.autoRotate;
      btnRot.textContent = "Auto-Rotate: " + (mv.autoRotate ? "On" : "Off");
    });
  }

  const btnReset = document.getElementById("btn-reset");
  if (btnReset && mv) {
    btnReset.addEventListener("click", function () {
      mv.cameraOrbit = "32deg 74deg auto";
      mv.fieldOfView = "auto";
    });
  }

  const ENVS = [
    { cls: "", label: "Backdrop: Sunset", exp: 1.05 },
    { cls: "env-moon", label: "Backdrop: Moonlit", exp: 0.92 },
    { cls: "env-studio", label: "Backdrop: Studio", exp: 1.18 }
  ];
  let envIdx = 0;
  const btnEnv = document.getElementById("btn-env");
  if (btnEnv && viewerCard && mv) {
    btnEnv.addEventListener("click", function () {
      envIdx = (envIdx + 1) % ENVS.length;
      viewerCard.classList.remove("env-moon", "env-studio");
      if (ENVS[envIdx].cls) {
        viewerCard.classList.add(ENVS[envIdx].cls);
      }
      mv.exposure = ENVS[envIdx].exp;
      btnEnv.textContent = ENVS[envIdx].label;
    });
  }

  // Arena Theme Switcher
  const arenaTabsEl = document.getElementById("arena-tabs");
  const arenaImg = document.getElementById("arena-img");
  const arenaTitle = document.getElementById("arena-title");
  const arenaWaves = document.getElementById("arena-waves");
  const arenaDesc = document.getElementById("arena-desc");
  const dotSun = document.getElementById("dot-sun");
  const dotAmb = document.getElementById("dot-amb");
  const dotHaze = document.getElementById("dot-haze");
  const hexSun = document.getElementById("hex-sun");
  const hexAmb = document.getElementById("hex-amb");
  const hexHaze = document.getElementById("hex-haze");

  function selectArena(idx) {
    const a = ARENAS[idx];
    document.querySelectorAll(".arena-tab").forEach(function (b, i) {
      b.classList.toggle("active", i === idx);
    });
    arenaImg.src = a.img;
    arenaImg.alt = a.name + " gameplay screenshot";
    arenaTitle.textContent = a.name;
    arenaWaves.textContent = a.waves;
    arenaDesc.textContent = a.desc;
    dotSun.style.backgroundColor = a.sun;
    dotAmb.style.backgroundColor = a.amb;
    dotHaze.style.backgroundColor = a.haze;
    hexSun.textContent = "Sun " + a.sun;
    hexAmb.textContent = "Ambient " + a.amb;
    hexHaze.textContent = "Haze " + a.haze;
  }

  if (arenaTabsEl) {
    ARENAS.forEach(function (a, idx) {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "arena-tab";
      b.textContent = "0" + (idx + 1) + " · " + a.name;
      b.addEventListener("click", function () {
        selectArena(idx);
      });
      arenaTabsEl.appendChild(b);
    });
    selectArena(0);
  }

  // Synthesized SFX Soundboard
  const padGrid = document.getElementById("pad-grid");
  const sfxRecipe = document.getElementById("sfx-recipe");
  let activeAudio = null;
  let activeBtn = null;

  if (padGrid) {
    SFX_LIST.forEach(function (s) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "sfx-pad";
      const st = document.createElement("strong");
      st.textContent = s.name;
      const sp = document.createElement("span");
      sp.textContent = s.meta;
      btn.appendChild(st);
      btn.appendChild(sp);
      btn.addEventListener("click", function () {
        if (activeAudio) {
          activeAudio.pause();
          activeAudio.currentTime = 0;
        }
        if (activeBtn) {
          activeBtn.classList.remove("playing");
        }
        const aud = new Audio("sfx/" + s.id + ".mp3");
        activeAudio = aud;
        activeBtn = btn;
        btn.classList.add("playing");
        if (sfxRecipe) {
          sfxRecipe.textContent = "# sfx/" + s.id + ".mp3\n" + s.recipe;
        }
        aud.addEventListener("ended", function () {
          btn.classList.remove("playing");
        });
        aud.play().catch(function () {
          btn.classList.remove("playing");
        });
      });
      padGrid.appendChild(btn);
    });
  }
})();
