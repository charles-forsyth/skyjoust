extends SceneTree
## Captures 4 real Forward+ 1920x1080 frames for visual QA:
## 1. Title screen (mode prompts)
## 2. Two-column Help & Rules card
## 3. Active Wave 4 combat (Bounder + Hunter + Shadowlord + Player with hinged wings + Shield + Dash HUD)
## 4. Peaceful Flight mode (golden eggs on sky islands)

func _snap(vp: Viewport, out_path: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var img := vp.get_texture().get_image()
	img.save_png(out_path)
	print("SAVED ", out_path, " ", img.get_size())


func _initialize() -> void:
	var out_dir := ProjectSettings.globalize_path("res://../renders/")
	AudioServer.set_bus_mute(0, true)
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame

	# 1. Title screen
	await _snap(root, out_dir + "final_title.png")

	# 2. Help card toggled open
	m._on_toggle_help()
	await _snap(root, out_dir + "final_help.png")
	m._on_toggle_help()

	# 3. Active combat showcase (all 3 V2 enemy knights + player + hinged wings + shield + long lance)
	m._start_game(m.Mode.DAILY)
	m._apply_theme(0)
	m.banner.visible = false
	m.sub.visible = false
	m.pending_spawns.clear()
	for x in m.enemies:
		x.queue_free()
	m.enemies.clear()
	m.player.spawn_t = 0.0
	m.player.invuln = 0.0
	m.player.pos = Vector2(-2.2, 8.6)
	m.player.vel = Vector2(6.5, 2.0)
	m.player.facing = 1
	m.player.flap_anim = 0.72
	m.shield = 999.0
	m.long_lance = 9.4
	m._power_tick(0.016)
	var placements := [
		[Rider.Kind.HUNTER, Vector2(2.4, 7.6), -1, 0.65],
		[Rider.Kind.BOUNDER, Vector2(-8.2, 10.6), 1, 0.45],
		[Rider.Kind.SHADOW, Vector2(8.0, 10.2), -1, 0.80],
	]
	for pl in placements:
		var e := Rider.new()
		m.add_child(e)
		e.setup(pl[0], pl[1], pl[2])
		e.spawn_t = 0.0
		e.grounded = false
		e.flap_anim = pl[3]
		m.enemies.append(e)
	m._drop_egg(Vector2(0.2, 6.95), Vector2.ZERO, 1)
	m._update_visuals(0.05)
	m._update_hud()
	await _snap(root, out_dir + "final_action_v2.png")

	# 4. Peaceful Flight mode on Moonlit Ruins
	m._start_game(m.Mode.PEACEFUL)
	m._apply_theme(1)
	m.banner.visible = false
	m.player.spawn_t = 0.0
	m.player.invuln = 0.0
	m.player.pos = Vector2(-1.5, 9.2)
	m.player.facing = 1
	m.player.flap_anim = 0.6
	m._update_visuals(0.05)
	m._update_hud()
	await _snap(root, out_dir + "final_peaceful.png")

	m.queue_free()
	await process_frame
	quit(0)
