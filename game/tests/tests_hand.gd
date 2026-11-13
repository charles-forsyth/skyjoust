extends SceneTree
## Headless check: the lava hand reaches for a rider skimming the lava and drags it down.
func _initialize():
	var m = load("res://main.tscn").instantiate()
	m.sim_seconds = 0.0
	root.add_child(m)
	await process_frame
	m.demo = true
	m._start_game()
	m.wave = 3
	m.pending_spawns.clear()
	for e in m.enemies: e.queue_free()
	m.enemies.clear()
	var e = Rider.new()
	m.add_child(e)
	e.setup(Rider.Kind.BOUNDER, Vector2(12.0, 0.6), 1)
	e.spawn_t = 0.0
	m.enemies.append(e)
	m.player.pos = Vector2(0, 12)
	m.player.invuln = 99.0
	m.hand_cd = 0.0
	var dt := 1.0 / 60.0
	var grabbed := false
	for i in 240:
		if m.hand_target == null:
			e.pos.y = minf(e.pos.y, 1.5)   # keep it skimming until grabbed
		m._hand_tick(dt)
		e.step(dt, 0.0, false, m.PLATS, m.HALF)
		if m.hand_target == e: grabbed = true
		if not is_instance_valid(e) or not m.enemies.has(e):
			print("HAND TEST PASS: rider pulled into lava at frame ", i)
			quit()
			return
	print("HAND TEST FAIL grabbed=", grabbed, " e.pos=", e.pos)
	quit()
