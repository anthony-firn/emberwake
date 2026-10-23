extends SceneTree
## Renders the three rigged characters through a walk cycle and their attacks, for checking animation by eye.
## godot4 --path . --rendering-driver opengl3 --write-movie poses.avi --fixed-fps 10 -s tests/pose_sheet.gd

var game: Node3D
var rigs := []
var frame := 0

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.mode = "sheet"
	game.hud_ui.hide()
	game.menu_ui.hide()
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40,40)
	floor.mesh = plane
	floor.material_override = game._make_material(Color("2a2733"))
	root.add_child(floor)
	var models := [[game.MODEL_HERO,"knight",2.0],[game.MODEL_SHADE,"shade",1.75],[game.MODEL_GUARDIAN,"guardian",1.9]]
	for i in models.size():
		var model: Node3D = models[i][0].instantiate()
		root.add_child(model)
		model.scale = Vector3.ONE*models[i][2]
		model.position = Vector3((i-1)*4.2,0,0)
		model.rotation.y = .6
		rigs.append(game._rig(model,models[i][1]))
	var light := OmniLight3D.new()
	light.position = Vector3(2,7,7)
	light.omni_range = 30
	light.light_energy = 2.5
	root.add_child(light)
	var cam: Camera3D = game.camera
	cam.position = Vector3(0,4.2,12.5)
	cam.look_at(Vector3(0,2.0,0))

func _process(_delta: float) -> bool:
	if rigs.is_empty(): return false
	frame += 1
	# Frames 1-16: walk cycle. Frames 17-36: attack from start to finish.
	for rig in rigs:
		if frame <= 16: game._pose(rig,1.0,frame*TAU/16.0,-1.0,frame*.1)
		else: game._pose(rig,0.0,0.0,float(frame-17)/19.0,frame*.1)
	return frame >= 36
