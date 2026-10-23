extends "res://tests/showreel.gd"
## Same scripted run, filmed by a side camera from the hero's front three-quarter view, for checking faces and animation.

var side_camera: Camera3D

func _process(delta: float) -> bool:
	var done := super(delta)
	if game != null and game.mode != "menu":
		if side_camera == null:
			side_camera = Camera3D.new()
			side_camera.fov = 50
			root.add_child(side_camera)
			side_camera.current = true
		var f: Vector3 = game.player.facing
		var r := Vector3(-f.z,0,f.x)
		side_camera.position = game.player.pos + f*8.5 + r*5.0 + Vector3(0,5.0,0)
		side_camera.look_at(game.player.pos + f*2.0 + Vector3(0,2.2,0))
	return done
