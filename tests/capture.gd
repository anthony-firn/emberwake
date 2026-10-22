extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var packed: PackedScene = load("res://main.tscn")
	var game: Node3D = packed.instantiate()
	root.add_child(game)
	await process_frame
	game._start_run()
	await create_timer(.7).timeout
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("/tmp/emberwake-capture.png")
	print("Saved capture: ",image.get_size())
	quit()
