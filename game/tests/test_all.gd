extends SceneTree
## Headless regression suite covering every bug fixed in the session review:
## 1. Settings save preserves high score ([score] best survives Sfx._save())
## 2. Pterodactyl kill sets 25s cooldown (no next-frame respawn loop) and respects shield
## 3. _start_game() resets powerups, _died_this_wave (Wave 1 Survival Bonus), hand state, and platforms
## 4. Screen-wrap bounce midpoint spawns near screen seam (|x| > 14), not arena centre (x = 0)
## 5. Egg tossed upward under a ledge bounces off the underside instead of phasing through
## 6. Lava troll hand grabs and pulls a low-skimming rider into the lava
## 7. Crumbling edge ledge falls after 1.3s standing and regrows after 7s
## 8. ModelFit.outline() attaches next_pass on material_override meshes (_build_hand)
## 9. Seeded determinism: two identical sim runs produce identical score/kills/rng state

var passes := 0
var fails := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		fails += 1


func _initialize() -> void:
	var dt := 1.0 / 60.0
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame

	# 1. Settings save preserves [score] best
	var cfg := ConfigFile.new()
	var prev_existed := cfg.load("user://settings.cfg") == OK
	var prev_best: int = cfg.get_value("score", "best", 0) if prev_existed else 0
	var prev_music: bool = m.sfx.music_on
	var prev_muted: bool = m.sfx.muted
	m.demo = false
	m.best = 0
	m.score = 42420
	m._save_best()
	m.sfx.toggle_mute()
	m.sfx.toggle_mute()
	var cfg2 := ConfigFile.new()
	cfg2.load("user://settings.cfg")
	_check(int(cfg2.get_value("score", "best", -1)) == 42420, "Sfx._save() preserves [score] best")
	# restore user's real best score
	cfg2.set_value("score", "best", prev_best)
	cfg2.set_value("audio", "music", prev_music)
	cfg2.set_value("audio", "muted", prev_muted)
	cfg2.save("user://settings.cfg")
	m.demo = true
	AudioServer.set_bus_mute(0, true)

	# 2. Pterodactyl kill cooldown + shield protection
	m._start_game()
	m.pending_spawns.clear()
	for x in m.enemies:
		x.queue_free()
	m.enemies.clear()
	var dummy := Rider.new()
	m.add_child(dummy)
	dummy.setup(Rider.Kind.BOUNDER, Vector2(-10, 10.1), 1)
	dummy.spawn_t = 99.0
	m.enemies.append(dummy)
	m.wave_t = 45.0
	m._ptero_tick(dt)
	_check(m.ptero_alive, "Pterodactyl spawns after PTERO_AFTER")
	# test shield blocks off-axis pterodactyl hit without dying
	m.shield = 999.0
	m.player.spawn_t = 0.0
	m.player.invuln = 0.0
	m.player.pos = Vector2(0.0, 7.0)
	m.player.facing = 1
	m.ptero_pos = Vector2(0.5, m.player.lance_y() + 0.85)  # body hit, outside beak tolerance
	m.ptero_vel = Vector2(-10.5, 0.0)
	var lives_before: int = m.lives
	m._ptero_tick(dt)
	_check(m.lives == lives_before and m.shield == 0.0 and m.state == m.State.PLAY, "Shield absorbs non-beak pterodactyl hit")
	# test beak kill sets cooldown and does NOT respawn on next ticks
	m.player.invuln = 0.0
	m.player.pos = Vector2(0.0, 7.0)
	m.player.facing = 1
	m.ptero_pos = Vector2(0.8, m.player.lance_y())
	m.ptero_vel = Vector2(-10.5, 0.0)
	m._ptero_tick(dt)
	_check(not m.ptero_alive and int(m.stats["ptero"]) >= 1, "Lance at beak height kills pterodactyl")
	m.hitstop = 0.0
	m._ptero_tick(dt)
	_check(not m.ptero_alive and m.ptero_next_t > m.wave_t + 20.0, "Pterodactyl does not respawn on next frame after kill")

	# 3. _start_game() resets powerups, _died_this_wave, and crumbled platforms
	m._drop_power(Vector2(2, 6), "shield")
	m.plat_on[1] = false
	m.live_plats.clear()
	m.stats["_died_this_wave"] = true
	m._start_game()
	_check(m.powerups.is_empty() and m.plat_on[1] and m.live_plats.size() == m.PLATS.size() and m.stats["_died_this_wave"] == false, "_start_game() clears powerups, restores platforms, and resets _died_this_wave")
	# clear Wave 1 cleanly and verify 3000 survival bonus
	m.pending_spawns.clear()
	for x in m.enemies:
		x.queue_free()
	m.enemies.clear()
	m.score = 500
	m._tick(dt, [0.0, false])
	_check(m.state == m.State.WAVE_CLEAR and m.score == 3500, "Restarted Wave 1 awards 3000 Survival Bonus")

	# 4. Screen-wrap bounce midpoint
	var dx: float = m._wrap_dx(14.8, -14.8)
	var mid_x: float = m._wrap_x(14.8 + dx * 0.5)
	_check(absf(dx - 0.4) < 0.01 and absf(mid_x) > 14.5, "Wrap-seam clash midpoint stays at screen edge")

	# 5. Egg ceiling bounce under centre ledge (PLATS[3] = Rect2(-4.0, 6.2, 7.5, 0.7))
	var g := Egg.new()
	m.add_child(g)
	g.setup(Vector2(0.0, 5.2), Vector2(0.0, 8.0), 0)
	var crossed_above := false
	for i in 40:
		g.step(dt, m.PLATS, m.HALF)
		if g.pos.y >= 6.85:
			crossed_above = true
	_check(not crossed_above, "Upward-popped egg bounces off ledge underside instead of phasing through")
	g.queue_free()

	# 6. Lava hand grabs skimming rider + ModelFit.outline works on material_override
	m._start_game()
	m.wave = 3
	m.pending_spawns.clear()
	for x in m.enemies:
		x.queue_free()
	m.enemies.clear()
	var sk := Rider.new()
	m.add_child(sk)
	sk.setup(Rider.Kind.BOUNDER, Vector2(12.0, 0.6), 1)
	sk.spawn_t = 0.0
	m.enemies.append(sk)
	m.player.pos = Vector2(0, 12)
	m.player.invuln = 99.0
	m.hand_cd = 0.0
	var pulled := false
	for i in 240:
		if m.hand_target == null:
			sk.pos.y = minf(sk.pos.y, 1.5)
		m._hand_tick(dt)
		sk.step(dt, 0.0, false, m.PLATS, m.HALF)
		if not is_instance_valid(sk) or not m.enemies.has(sk):
			pulled = true
			break
	_check(pulled, "Lava hand grabs and drags skimming rider into lava")
	var arm_mesh := m.hand.get_child(0) as MeshInstance3D
	_check(arm_mesh.material_override != null and arm_mesh.material_override.next_pass != null, "ModelFit.outline attaches next_pass to material_override meshes")

	# 7. Crumbling ledge falls and regrows
	m._start_game()
	m.wave = 6
	m.pending_spawns.clear()
	for x in m.enemies:
		x.queue_free()
	m.enemies.clear()
	var lr: Rect2 = m.PLATS[1]
	m.player.pos = Vector2(lr.get_center().x, lr.end.y + 0.01)
	m.player.vel = Vector2.ZERO
	m.player.spawn_t = 0.0
	var fell_at := -1
	var back_at := -1
	for i in 600:
		m._tick(dt, [0.0, false])
		if fell_at < 0 and not m.plat_on[1]:
			fell_at = i
		if fell_at >= 0 and back_at < 0 and m.plat_on[1]:
			back_at = i
	_check(fell_at > 0 and back_at > fell_at, "Crumbling edge ledge falls and regrows")

	# 8. Player visual attachments (shield shader, lance beam, flight wings)
	_check(m.player.shield_fx != null and m.player.shield_fx.material_override is ShaderMaterial, "Player shield bubble uses fresnel ShaderMaterial")
	_check(m.player.lance_fx != null and m.player.wings.size() == 2, "Player has Long Lance beam and 2 articulated flight wings")

	# 9. Determinism: identical seed + _update_visuals vs _tick-only produces identical gameplay state
	m.rng.seed = 7777
	m._start_game()
	for i in 600:
		m._tick(dt, m._autopilot())
		m._update_visuals(dt)
	var score_with_vis: int = m.score
	var pos_with_vis: Vector2 = m.player.pos
	m.rng.seed = 7777
	m._start_game()
	for i in 600:
		m._tick(dt, m._autopilot())
	_check(m.score == score_with_vis and m.player.pos.distance_to(pos_with_vis) < 0.0001, "Gameplay RNG is deterministic regardless of _update_visuals")

	# 10. Hinged multi-feather wings (WingRight/Left + WristRight/Left)
	_check(m.player.wrists.size() == 2 and m.player.wrists[0] != null and m.player.wrists[1] != null, "Hinged primary-feather wrists loaded from wing_feathered.glb")
	m.player.flap_anim = 0.8
	m.player.sync_visual(dt)
	var wr_down: float = m.player.wrists[0].rotation.x
	m.player.flap_anim = 0.0
	m.player.sync_visual(dt)
	var wr_up: float = m.player.wrists[0].rotation.x
	_check(wr_down > 0.0 and wr_up < 0.0, "Wing wrist extends on downstroke and flexes on recovery")

	# 11. Air-Dash lunge speed, cooldown, and +0.20 tie-break lance advantage
	m._start_game()
	m.pending_spawns.clear()
	for x in m.enemies:
		x.queue_free()
	m.enemies.clear()
	m.player.spawn_t = 0.0
	m.player.invuln = 0.0
	m.player.pos = Vector2(-2.0, 7.05)
	m.player.facing = 1
	m.player.step(dt, 1.0, false, m.PLATS, m.HALF, true)
	_check(m.player.dashed and m.player.dashing() and absf(m.player.vel.x - Rider.DASH_V) < 0.01 and m.player.dash_cd > 2.0, "Air-Dash surges at DASH_V and starts cooldown")
	m.player.step(dt, 1.0, false, m.PLATS, m.HALF, true)
	_check(not m.player.dashed, "Air-Dash cannot re-trigger while on cooldown")
	var rival := Rider.new()
	m.add_child(rival)
	rival.setup(Rider.Kind.HUNTER, Vector2(m.player.pos.x + 0.3, m.player.pos.y - 0.08), -1)
	rival.spawn_t = 0.0
	m.enemies.append(rival)
	# Without dash, +0.08 height is < JOUST_MARGIN (0.22) -> bounce; with dash (+0.20 -> 0.28) -> kill!
	m._collisions()
	_check(m.enemies.is_empty() and m.slowmo_t > 0.15, "Air-Dash tie-break slays near-level rival and wave-final kill triggers slow-mo")

	# 12. Daily Challenge deterministic seed
	m._start_game(m.Mode.DAILY)
	var daily_spawns_a: Array = m.pending_spawns.duplicate()
	m._start_game(m.Mode.DAILY)
	var daily_spawns_b: Array = m.pending_spawns.duplicate()
	_check(daily_spawns_a == daily_spawns_b and not daily_spawns_a.is_empty(), "Daily Challenge produces deterministic wave spawns")

	# 13. Peaceful Flight mode: 0 enemies, 5 golden eggs, non-hatching, lava updraft, theme tour
	m._start_game(m.Mode.PEACEFUL)
	_check(m.enemies.is_empty() and m.pending_spawns.is_empty() and m.eggs.size() == 5, "Peaceful Flight starts with 5 golden eggs and 0 enemies")
	m.player.spawn_t = 0.0
	for i in 900:
		m._tick(dt, [0.0, false])
	_check(m.enemies.is_empty() and m.eggs.size() == 5, "Peaceful Flight eggs never hatch into enemies")
	var p_lives: int = m.lives
	m.player.pos = Vector2(12.0, m.LAVA_Y - 0.3)
	m.player.vel = Vector2(0.0, -8.0)
	m._tick(dt, [0.0, false])
	_check(m.lives == p_lives and m.state == m.State.PLAY and m.player.vel.y > 9.0, "Peaceful Flight lava gently updrafts player without losing a life")
	var t0: int = m.theme_idx
	for i in 10:
		m._collect_egg(m.eggs[0])
		m._replenish_peaceful_eggs()
	_check(m.peaceful_eggs == 10 and m.theme_idx != t0, "Peaceful Flight cycles arena theme every 10 golden eggs")

	# 14. Help overlay + Quit to Title from Pause
	m.demo = false
	m._on_toggle_help()
	_check(m.help_panel.visible, "Help card toggles open")
	m._on_toggle_pause()
	_check(paused, "Pause freezes SceneTree")
	m._return_to_title()
	_check(not paused and m.state == m.State.TITLE and m.enemies.is_empty() and m.eggs.is_empty(), "Quit to Title unpauses and cleans arena")
	m.demo = true

	m.queue_free()
	await process_frame
	if fails == 0:
		print("ALL %d REGRESSION CHECKS PASSED" % passes)
	else:
		print("FAILED CHECKS: ", fails)
	quit(1 if fails > 0 else 0)
