extends SceneTree
## Headless check: standing on an edge ledge at wave 6+ makes it crumble, then it respawns.
func _initialize():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.demo = true
	m._start_game()
	m.wave = 6
	m.pending_spawns.clear()
	for x in m.enemies: x.queue_free()
	m.enemies.clear()
	var r: Rect2 = m.PLATS[1]
	m.player.pos = Vector2(r.get_center().x, r.end.y + 0.01)
	m.player.vel = Vector2.ZERO
	m.player.spawn_t = 0.0
	var dt := 1.0 / 60.0
	var fell_at := -1
	var back_at := -1
	for i in 900:
		m._tick(dt, [0.0, false])
		if fell_at < 0 and not m.plat_on[1]: fell_at = i
		if fell_at >= 0 and back_at < 0 and m.plat_on[1]: back_at = i
	if fell_at > 0 and back_at > fell_at:
		print("CRUMBLE TEST PASS: fell at frame ", fell_at, ", back at ", back_at)
	else:
		print("CRUMBLE TEST FAIL fell=", fell_at, " back=", back_at, " grounded=", m.player.grounded, " p=", m.player.pos)
	quit()
