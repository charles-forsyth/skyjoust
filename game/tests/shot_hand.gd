extends SceneTree
## Capture helper: lava hand grabbing an enemy (render with --write-movie).
var m
var e
func _initialize():
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.demo = true
	m._start_game()
	m.wave = 3
	m.pending_spawns.clear()
	for x in m.enemies: x.queue_free()
	m.enemies.clear()
	e = Rider.new()
	m.add_child(e)
	e.setup(Rider.Kind.BOUNDER, Vector2(11.5, 1.0), -1)
	e.spawn_t = 0.0
	m.enemies.append(e)
	m.player.pos = Vector2(-3, 12)
	m.player.invuln = 99.0
	m.hand_cd = 0.0
	m.demo = true


func _process(_d: float) -> bool:
	if is_instance_valid(e) and m.hand_target != e:
		e.pos.y = minf(e.pos.y, 1.4)
		e.vel.y = minf(e.vel.y, 0.0)
	return false
