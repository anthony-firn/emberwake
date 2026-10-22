extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var packed: PackedScene = load("res://main.tscn")
	var game: Node3D = packed.instantiate()
	root.add_child(game)
	await process_frame
	game._start_run()
	await process_frame
	assert(game.mode == "playing")
	assert(game.rooms.size() == 9)
	assert(game._coord_for(Vector3.ZERO) == Vector2i.ZERO)
	assert(game._solid(Vector3(-9*game.TILE,0,-9*game.TILE)))
	assert(not game._solid(Vector3.ZERO))
	var room: Dictionary = game._room(Vector2i(1,0))
	for lane in range(8,11):
		for tile in range(1,18):
			assert(room.tiles[lane][tile] == 0)
			assert(room.tiles[tile][lane] == 0)
	game._spawn_room(room)
	assert(game.enemies.size() > 0)
	var observed: Dictionary = game.agent_observe()
	assert(observed.mode == "playing")
	game._gain_xp(100)
	assert(game.mode == "upgrade")
	game._choose_blessing(0)
	assert(game.mode == "playing")
	game._hurt(10000)
	assert(game.mode == "dead")
	game.agent_act({"restart":true})
	assert(game.mode == "playing")
	print("EMBERWAKE SMOKE PASS: run, room, collision, enemies, upgrades, death, restart")
	game.queue_free()
	await process_frame
	quit()
