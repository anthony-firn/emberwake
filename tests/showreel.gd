extends SceneTree
## Scripted run for gameplay videos: hunt the nearest enemy, strike in range, dash now and then.
## Render: godot4 --path . --rendering-driver opengl3 --resolution 1280x720 --write-movie out.avi --fixed-fps 30 -s tests/showreel.gd
## Set SHOWREEL_SECONDS to change the length (default 30).

var game: Node3D
var frame := 0
var last_pos := Vector3.ZERO
var stuck := 0
var detour := Vector3.ZERO
var FRAMES := 30 * int(OS.get_environment("SHOWREEL_SECONDS")) if OS.get_environment("SHOWREEL_SECONDS") != "" else 30 * 30

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.agent_enabled = true
	game.agent_waiting = false
	game._start_run()

func _process(_delta: float) -> bool:
	if game == null or game.mode == "menu":
		return false
	frame += 1
	if game.player.hp < 45.0:
		game.player.hp = game.player.max_hp
	if game.mode == "upgrade":
		game._choose_blessing(frame % 3)
	var target := Vector3.ZERO
	var best := INF
	for e in game.enemies:
		if not e.alive: continue
		var d: float = e.pos.distance_to(game.player.pos)
		if d < best:
			best = d
			target = e.pos
	var move := Vector3.ZERO
	if best < INF:
		var to: Vector3 = target - game.player.pos
		to.y = 0
		game.agent_aim = to.normalized()
		if best > 2.6:
			move = to.normalized()
		if best < 3.2 and frame % 9 == 0:
			game._strike()
		if best > 7.0 and frame % 70 == 0:
			game._dash()
	else:
		move = Vector3(sin(frame * .02), 0, -1).normalized()
		game.agent_aim = move
	# Walls block straight lines to enemies in other rooms; sidestep when progress stalls.
	if frame % 15 == 0:
		stuck = stuck + 1 if game.player.pos.distance_to(last_pos) < .5 and move.length() > 0 else 0
		last_pos = game.player.pos
		if stuck >= 2:
			detour = Vector3(-move.z, 0, move.x) * (1 if (frame / 15) % 2 == 0 else -1)
			stuck = 0
	if detour.length() > 0:
		move = (detour + move * .3).normalized()
		if frame % 45 == 0:
			detour = Vector3.ZERO
	game.agent_move = move
	return frame >= FRAMES
