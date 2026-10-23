extends Node3D

## EMBERWAKE: a native, endless, seeded 3D action roguelike.
const TILE := 2.35
const ROOM_TILES := 19
const ROOM_SIZE := TILE * ROOM_TILES
const HALF := 9
const MODEL_HERO := preload("res://assets/models/ember_knight.glb")
const MODEL_SHADE := preload("res://assets/models/shade.glb")
const MODEL_GUARDIAN := preload("res://assets/models/guardian.glb")
const MODEL_PILLAR := preload("res://assets/models/pillar.glb")
const MODEL_BRAZIER := preload("res://assets/models/brazier.glb")
const MODEL_SHRINE := preload("res://assets/models/shrine.glb")
const TITLE_FONT := preload("res://assets/fonts/Cinzel-Regular.ttf")
const BODY_FONT := preload("res://assets/fonts/Inter-Regular.ttf")

const PALETTES := [
	{"name":"THE ASHEN HALLS", "floor":Color("292b35"), "wall":Color("5a5357"), "trim":Color("8a6d60"), "light":Color("ff995d")},
	{"name":"THE MOSSBOUND CRYPT", "floor":Color("26352e"), "wall":Color("536b59"), "trim":Color("869773"), "light":Color("c5e49c")},
	{"name":"THE VIOLET VAULT", "floor":Color("302e3e"), "wall":Color("695e78"), "trim":Color("a58bb3"), "light":Color("d1a2f4")},
	{"name":"THE SUNKEN KEEP", "floor":Color("26353e"), "wall":Color("526d79"), "trim":Color("85a8ac"), "light":Color("82d6e8")},
]
const BLESSINGS := [
	{"name":"SEARING EDGE", "icon":"❖", "desc":"Deal 25% more sword damage.", "stat":"damage"},
	{"name":"SWIFTSTEP", "icon":"➶", "desc":"Move 15% faster.", "stat":"speed"},
	{"name":"IRON HEART", "icon":"♥", "desc":"Gain 30 maximum health and heal.", "stat":"health"},
	{"name":"WIDE ARC", "icon":"◈", "desc":"Strike farther and wider.", "stat":"range"},
	{"name":"QUICKENED STEEL", "icon":"⚔", "desc":"Attack 18% faster.", "stat":"attack"},
	{"name":"EMBERGUARD", "icon":"✹", "desc":"Take 15% less damage.", "stat":"armor"},
	{"name":"SOUL MAGNET", "icon":"◎", "desc":"Draw soulfire from farther away.", "stat":"magnet"},
	{"name":"BLOODFIRE", "icon":"❖", "desc":"Heal when you slay a foe.", "stat":"leech"},
	{"name":"PHANTOM DASH", "icon":"☄", "desc":"Dash more often.", "stat":"dash"},
]

var seed: int = 0
var mode := "menu"
var rooms := {}
var enemies: Array[Dictionary] = []
var souls: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var player := {}
var kills := 0
var seconds := 0.0
var camera: Camera3D
var world: Node3D
var actors: Node3D
var hero: Node3D
var sword_light: OmniLight3D
var ui: CanvasLayer
var menu_ui: Control
var hud_ui: Control
var overlay_ui: Control
var health_bar: ProgressBar
var xp_bar: ProgressBar
var health_label: Label
var xp_label: Label
var level_label: Label
var depth_label: Label
var room_label: Label
var kill_label: Label
var dash_label: Label
var tip_label: Label
var mini_map: Control
var chosen_blessings: Array[Dictionary] = []
var mouse_aim := Vector3.FORWARD
var target_position := Vector3.ZERO
var current_room := Vector2i.ZERO
var toast_time := 0.0
var message_label: Label
var attack_flash := 0.0
var screen_flash: ColorRect
var rng := RandomNumberGenerator.new()
var audio_player: AudioStreamPlayer
var agent_server: TCPServer
var agent_peer: StreamPeerTCP
var agent_buffer := ""
var agent_enabled := false
var agent_waiting := false
var agent_timer := 0.0
var agent_move := Vector3.ZERO
var agent_aim := Vector3.ZERO

func _ready() -> void:
	get_window().title = "EMBERWAKE — The Endless Descent"
	# Browsers have no system fonts to fall back on, so title text borrows symbols from the body font.
	TITLE_FONT.set_fallbacks([BODY_FONT])
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_create_scene()
	_create_audio()
	_create_ui()
	_show_menu()

func _exit_tree() -> void:
	if audio_player:
		audio_player.stop()
		audio_player.stream = null
	if agent_peer: agent_peer.disconnect_from_host()
	if agent_server: agent_server.stop()

func _create_scene() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0e19")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a5a1ba")
	env.ambient_light_energy = 0.53
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("1b1b2a")
	env.fog_density = 0.014
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-51, -32, 0)
	sun.light_color = Color("c9ad9f")
	sun.light_energy = 0.52
	sun.shadow_enabled = true
	add_child(sun)
	world = Node3D.new()
	world.name = "InfiniteLabyrinth"
	add_child(world)
	actors = Node3D.new()
	actors.name = "Actors"
	add_child(actors)
	camera = Camera3D.new()
	camera.name = "IsometricCamera"
	camera.current = true
	camera.fov = 47.0
	camera.position = Vector3(13, 18, 16)
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	if "--agent" in OS.get_cmdline_user_args():
		agent_server = TCPServer.new()
		var result := agent_server.listen(9327,"127.0.0.1")
		if result == OK:
			print("EMBERWAKE AGENT BRIDGE listening on 127.0.0.1:9327")
		else:
			push_error("Could not start agent bridge: %s" % result)

func _create_audio() -> void:
	if DisplayServer.get_name() == "headless": return
	audio_player = AudioStreamPlayer.new()
	audio_player.volume_db = -12
	add_child(audio_player)

func _tone(frequency: float, duration: float, brightness: float = .25, bend: float = 0.0) -> void:
	if audio_player == null: return
	var samples: int = roundi(duration*22050.0)
	var data := PackedByteArray()
	data.resize(samples*2)
	for i in samples:
		var progress: float = float(i)/float(maxi(1,samples))
		var phase: float = TAU*(frequency*progress*duration+bend*progress*progress*duration)
		var envelope: float = (1.0-progress)*(1.0-progress)
		var sample: float = (sin(phase)+sin(phase*2.01)*brightness)*envelope*.18
		data.encode_s16(i*2,clampi(roundi(sample*32767.0),-32768,32767))
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	wave.stereo = false
	wave.data = data
	audio_player.stream = wave
	audio_player.play()

func _start_run() -> void:
	for child in world.get_children(): child.queue_free()
	for child in actors.get_children(): child.queue_free()
	rooms.clear()
	enemies.clear()
	souls.clear()
	effects.clear()
	seed = randi()
	rng.seed = seed
	kills = 0
	seconds = 0.0
	current_room = Vector2i.ZERO
	player = {"pos":Vector3.ZERO, "hp":100.0, "max_hp":100.0, "xp":0, "xp_need":30, "level":1,
		"damage":27.0, "speed":9.0, "range":3.6, "arc":0.95, "attack_delay":0.37, "attack_cd":0.0,
		"dash_delay":2.2, "dash_cd":0.0, "dash_time":0.0, "dash_dir":Vector3.ZERO,
		"invulnerable":0.0, "armor":0.0, "magnet":4.2, "leech":0.0, "facing":Vector3(0,0,-1)}
	var first := _room(Vector2i.ZERO)
	first.seen = true
	first.spawned = true
	mode = "playing"
	_ensure_near_rooms()
	hero = MODEL_HERO.instantiate()
	hero.name = "EmberKnight"
	actors.add_child(hero)
	hero.scale = Vector3.ONE * 2.0
	hero.position = Vector3.ZERO
	sword_light = OmniLight3D.new()
	sword_light.light_color = Color("ff9e5f")
	sword_light.light_energy = 1.1
	sword_light.omni_range = 10.0
	sword_light.shadow_enabled = false
	hero.add_child(sword_light)
	sword_light.position.y = 1.2
	camera.position = player.pos + Vector3(13,18,16)
	camera.look_at(player.pos + Vector3(0,1,0))
	menu_ui.hide()
	overlay_ui.hide()
	hud_ui.show()
	_tone(430,.24,.2,340)
	_toast("THE FIRST EMBER")
	_update_hud()

func _hash_room(coord: Vector2i, salt: int = 0) -> int:
	var value: int = coord.x * 374761393 + coord.y * 668265263 + seed * 1442695041 + salt * 3266489917
	value = (value ^ (value >> 13)) * 1274126177
	return value ^ (value >> 16)

func _room(coord: Vector2i) -> Dictionary:
	if rooms.has(coord): return rooms[coord]
	var depth: int = abs(coord.x) + abs(coord.y)
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = _hash_room(coord)
	var tiles: Array = []
	for z in ROOM_TILES:
		var row: Array[int] = []
		for x in ROOM_TILES:
			var edge: bool = x == 0 or z == 0 or x == ROOM_TILES-1 or z == ROOM_TILES-1
			var door: bool = (x >= 8 and x <= 10 and (z == 0 or z == 18)) or (z >= 8 and z <= 10 and (x == 0 or x == 18))
			row.append(1 if edge and not door else 0)
		tiles.append(row)
	if depth > 0:
		var patterns := [Vector2i(4,4),Vector2i(14,4),Vector2i(4,14),Vector2i(14,14)]
		var offset: int = local_rng.randi_range(0,1)
		for p in patterns:
			if local_rng.randf() > .13: tiles[p.y + (1 if p.y < 9 else -1) * offset][p.x] = 2
	var biome: int = 0 if depth < 2 else local_rng.randi_range(0,PALETTES.size()-1)
	var room := {"coord":coord, "depth":depth, "tiles":tiles, "biome":biome, "seen":false, "spawned":false,
		"loaded":false, "node":null, "shrine":depth > 0 and local_rng.randf() > .81, "shrine_used":false}
	rooms[coord] = room
	return room

func _make_material(color: Color, roughness: float = 1.0, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.5
	return material

func _box(parent: Node3D, name: String, pos: Vector3, size: Vector3, material: Material, shadow: bool = true) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	box.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = material
	box.position = pos
	if not shadow: box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(box)
	return box

func _build_room(room: Dictionary) -> void:
	if room.loaded: return
	room.loaded = true
	var coord: Vector2i = room.coord
	var pal: Dictionary = PALETTES[room.biome]
	var node := Node3D.new()
	node.name = "Room_%s_%s" % [coord.x,coord.y]
	node.position = Vector3(coord.x*ROOM_SIZE,0,coord.y*ROOM_SIZE)
	world.add_child(node)
	room.node = node
	_box(node,"Floor",Vector3(0,-.29,0),Vector3(ROOM_SIZE,.6,ROOM_SIZE),_make_material(pal.floor))
	var inset := _make_material(pal.floor.lightened(.055))
	_box(node,"InnerFloor",Vector3(0,.015,0),Vector3(ROOM_SIZE-2.0,.028,ROOM_SIZE-2.0),inset,false)
	var grout := _make_material(pal.floor.darkened(.16))
	for line in range(-8,9,2):
		_box(node,"StoneSeam",Vector3(line*TILE,.036,0),Vector3(.025,.009,ROOM_SIZE-2.2),grout,false)
		_box(node,"StoneSeam",Vector3(0,.037,line*TILE),Vector3(ROOM_SIZE-2.2,.009,.025),grout,false)
	var rune := _make_material(pal.trim.darkened(.08),.5,pal.light.darkened(.7))
	for ring in [4.8,7.2]:
		for i in 24:
			var angle: float = TAU*float(i)/24.0
			var mark := _box(node,"FloorRune",Vector3(cos(angle)*ring,.054,sin(angle)*ring),Vector3(.68,.012,.065),rune,false)
			mark.rotation.y = -angle
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(TILE,3.5,TILE)
	var wall_count := 0
	for z in ROOM_TILES:
		for x in ROOM_TILES:
			if room.tiles[z][x] == 1: wall_count += 1
	var walls := MultiMeshInstance3D.new()
	walls.name = "CarvedWalls"
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.instance_count = wall_count
	multi.mesh = wall_mesh
	walls.multimesh = multi
	walls.material_override = _make_material(pal.wall)
	node.add_child(walls)
	var index := 0
	for z in ROOM_TILES:
		for x in ROOM_TILES:
			if room.tiles[z][x] != 1: continue
			multi.set_instance_transform(index,Transform3D(Basis(),Vector3((x-HALF)*TILE,1.75,(z-HALF)*TILE)))
			index += 1
	var edge_mat := _make_material(pal.trim)
	for side in [-1,1]:
		for lane in [-1,1]:
			var p := Vector3(side*HALF*TILE,2.95,lane*5*TILE)
			_box(node,"WallSigil",p,Vector3(.14,.32,1.2),edge_mat,false)
			_box(node,"WallSigil",Vector3(lane*5*TILE,2.95,side*HALF*TILE),Vector3(1.2,.32,.14),edge_mat,false)
	for z in ROOM_TILES:
		for x in ROOM_TILES:
			if room.tiles[z][x] != 2: continue
			var pillar := MODEL_PILLAR.instantiate()
			pillar.position = Vector3((x-HALF)*TILE,0,(z-HALF)*TILE)
			pillar.scale = Vector3.ONE * 1.65
			node.add_child(pillar)
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = _hash_room(coord,77)
	var crack_mat := _make_material(pal.trim.darkened(.28))
	for i in 36:
		var x: int = local_rng.randi_range(2,16)
		var z: int = local_rng.randi_range(2,16)
		if room.tiles[z][x] != 0: continue
		var mark := _box(node,"FloorInscription",Vector3((x-HALF)*TILE,.035,(z-HALF)*TILE),Vector3(local_rng.randf_range(.25,.9),.012,.035),crack_mat,false)
		mark.rotation.y = local_rng.randf_range(-1.3,1.3)
	for px in [-7,7]:
		for pz in [-7,7]:
			if local_rng.randf() < .32: continue
			var brazier := MODEL_BRAZIER.instantiate()
			brazier.position = Vector3(px*TILE,0,pz*TILE)
			brazier.scale = Vector3.ONE * 1.65
			node.add_child(brazier)
			var light := OmniLight3D.new()
			light.light_color = pal.light
			light.light_energy = 1.15
			light.omni_range = 8.7
			light.position = brazier.position + Vector3(0,1.7,0)
			node.add_child(light)
	if room.shrine:
		var shrine := MODEL_SHRINE.instantiate()
		shrine.name = "Shrine"
		shrine.position = Vector3.ZERO
		shrine.scale = Vector3.ONE * 1.8
		node.add_child(shrine)
		var light := OmniLight3D.new()
		light.light_color = pal.light
		light.omni_range = 10
		light.light_energy = 1.5
		light.position = Vector3(0,2.1,0)
		node.add_child(light)

func _ensure_near_rooms() -> void:
	var needed := {}
	for dz in range(-1,2):
		for dx in range(-1,2):
			var coord := current_room + Vector2i(dx,dz)
			needed[coord] = true
			_build_room(_room(coord))
	for coord in rooms.keys():
		var room: Dictionary = rooms[coord]
		if room.loaded and not needed.has(coord):
			room.node.queue_free()
			room.node = null
			room.loaded = false

func _coord_for(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x+ROOM_SIZE*.5)/ROOM_SIZE),floori((pos.z+ROOM_SIZE*.5)/ROOM_SIZE))

func _solid(pos: Vector3, radius: float = .55) -> bool:
	for dx in [-radius,radius]:
		for dz in [-radius,radius]:
			var point := pos + Vector3(dx,0,dz)
			var coord := _coord_for(point)
			var lx: int = clampi(roundi((point.x-coord.x*ROOM_SIZE)/TILE)+HALF,0,ROOM_TILES-1)
			var lz: int = clampi(roundi((point.z-coord.y*ROOM_SIZE)/TILE)+HALF,0,ROOM_TILES-1)
			if _room(coord).tiles[lz][lx] != 0: return true
	return false

func _move_actor(pos: Vector3, delta_pos: Vector3, radius: float = .55) -> Vector3:
	var next := pos
	if not _solid(pos+Vector3(delta_pos.x,0,0),radius): next.x += delta_pos.x
	if not _solid(next+Vector3(0,0,delta_pos.z),radius): next.z += delta_pos.z
	return next

func _spawn_room(room: Dictionary) -> void:
	if room.spawned or room.depth == 0: return
	room.spawned = true
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = _hash_room(room.coord,55)
	var count: int = mini(12,3 + room.depth/3 + local_rng.randi_range(0,2))
	for i in count:
		var position := Vector3.ZERO
		for attempt in 30:
			position = Vector3(room.coord.x*ROOM_SIZE + local_rng.randf_range(-7,7)*TILE,0,room.coord.y*ROOM_SIZE + local_rng.randf_range(-7,7)*TILE)
			if not _solid(position,.8) and position.distance_to(player.pos) > 5.0: break
		var guardian: bool = local_rng.randf() < minf(.35,.13+room.depth*.019)
		var enemy_model: Node3D = MODEL_GUARDIAN.instantiate() if guardian else MODEL_SHADE.instantiate()
		actors.add_child(enemy_model)
		enemy_model.scale = Vector3.ONE * (1.9 if guardian else 1.75)
		enemy_model.position = position
		var max_hp: float = (88.0 if guardian else 49.0) * (1.0 + room.depth*.085)
		enemies.append({"node":enemy_model,"pos":position,"room":room.coord,"hp":max_hp,"max_hp":max_hp,
			"speed":3.2 if guardian else 4.5,"damage":20.0 if guardian else 12.0,"guardian":guardian,
			"attack_cd":local_rng.randf(),"stun":0.0,"flash":0.0,"phase":local_rng.randf()*TAU,"alive":true})
	if room.shrine: _toast("A FORGOTTEN SHRINE")

func _process(delta: float) -> void:
	_poll_agent(delta)
	if mode != "playing": return
	if agent_enabled and agent_waiting: return
	var dt: float = minf(delta,.04)
	seconds += dt
	_update_player(dt)
	_update_enemies(dt)
	_update_souls(dt)
	_update_effects(dt)
	_update_camera(dt)
	_update_hud()
	if toast_time > 0:
		toast_time -= dt
		message_label.modulate.a = minf(1.0,toast_time*.8)
		if toast_time <= 0: message_label.hide()

func _update_player(dt: float) -> void:
	player.attack_cd = maxf(0.0,player.attack_cd-dt)
	player.dash_cd = maxf(0.0,player.dash_cd-dt)
	player.invulnerable = maxf(0.0,player.invulnerable-dt)
	var input := agent_move if agent_enabled else Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input.x += 1
	input = input.normalized()
	if player.dash_time > 0:
		player.dash_time -= dt
		player.pos = _move_actor(player.pos,player.dash_dir*29.0*dt)
		if rng.randf() < .55: _spark(player.pos+Vector3(0,.6,0),Color("ffb371"),.45)
	else:
		player.pos = _move_actor(player.pos,input*player.speed*dt)
	_update_aim(input)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_J): _strike()
	hero.position = player.pos
	hero.rotation.y = atan2(player.facing.x,player.facing.z) + PI
	hero.position.y = sin(seconds*9.0)*.045 if input.length() > 0 else 0.0
	sword_light.light_energy = 1.05 + sin(seconds*7.0)*.16
	var room_coord := _coord_for(player.pos)
	if room_coord != current_room:
		current_room = room_coord
		_ensure_near_rooms()
		var room: Dictionary = _room(room_coord)
		if not room.seen:
			room.seen = true
			_toast(PALETTES[room.biome].name)
		_spawn_room(room)
	if player.invulnerable > 0: hero.visible = int(seconds*18.0)%2 == 0
	else: hero.visible = true

func _update_aim(input: Vector3) -> void:
	if agent_enabled:
		if agent_aim.length() > .01: player.facing = agent_aim.normalized()
		elif input.length() > 0: player.facing = input.normalized()
		return
	var pointer := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(pointer)
	var direction := camera.project_ray_normal(pointer)
	if absf(direction.y) > .001:
		var t: float = -from.y/direction.y
		if t > 0:
			target_position = from + direction*t
			var aim: Vector3 = target_position-player.pos
			aim.y = 0
			if aim.length() > .6:
				player.facing = aim.normalized()
				return
	if input.length() > 0: player.facing = input

func _strike() -> void:
	if player.attack_cd > 0 or mode != "playing": return
	player.attack_cd = player.attack_delay
	_tone(270,.10,.5,-170)
	attack_flash = .18
	var dir: Vector3 = player.facing
	var slash_pos: Vector3 = player.pos + dir*2.25 + Vector3(0,.85,0)
	var flash := OmniLight3D.new()
	flash.light_color = Color("ffd5a1")
	flash.light_energy = 3.7
	flash.omni_range = 5.5
	flash.position = slash_pos
	actors.add_child(flash)
	effects.append({"node":flash,"time":.16,"max":.16,"kind":"flash"})
	for e in enemies:
		if not e.alive: continue
		var difference: Vector3 = e.pos-player.pos
		difference.y = 0
		if difference.length() > player.range+1.0: continue
		if dir.dot(difference.normalized()) < cos(player.arc): continue
		_damage_enemy(e,player.damage)
		var knock: Vector3 = difference.normalized()*.65
		e.pos = _move_actor(e.pos,knock,.7)
	for i in 10:
		var angle: float = atan2(dir.x,dir.z) + rng.randf_range(-player.arc,player.arc)
		var spark_dir := Vector3(sin(angle),rng.randf_range(-.1,.4),cos(angle))
		_spark(slash_pos+spark_dir*rng.randf_range(.1,1.5),Color("ffd5a1"),.18)

func _dash() -> void:
	if mode != "playing" or player.dash_cd > 0: return
	var direction := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): direction.z -= 1
	if Input.is_key_pressed(KEY_S): direction.z += 1
	if Input.is_key_pressed(KEY_A): direction.x -= 1
	if Input.is_key_pressed(KEY_D): direction.x += 1
	if direction == Vector3.ZERO: direction = player.facing
	player.dash_dir = direction.normalized()
	player.dash_time = .20
	player.dash_cd = player.dash_delay
	player.invulnerable = .30
	_tone(390,.16,.3,330)
	for i in 14: _spark(player.pos+Vector3(0,.7,0),Color("ffad6b"),.55)

func _update_enemies(dt: float) -> void:
	for e in enemies:
		if not e.alive: continue
		e.attack_cd -= dt
		e.stun = maxf(0.0,e.stun-dt)
		e.flash = maxf(0.0,e.flash-dt)
		e.phase += dt*2.0
		var to_player: Vector3 = player.pos-e.pos
		var distance: float = to_player.length()
		if distance < 20.0 and e.stun <= 0:
			if distance > 1.3:
				e.pos = _move_actor(e.pos,to_player.normalized()*e.speed*dt,.75)
			elif e.attack_cd <= 0:
				_hurt(e.damage)
				e.attack_cd = 1.5 if e.guardian else 1.1
		e.node.position = e.pos + Vector3(0,sin(e.phase)*.035,0)
		if distance > .1: e.node.rotation.y = atan2(to_player.x,to_player.z)+PI
		var base_scale: float = 1.9 if e.guardian else 1.75
		if e.flash > 0: e.node.scale = Vector3.ONE * base_scale * (1.0+e.flash*.55)
		else: e.node.scale = Vector3.ONE * base_scale

func _damage_enemy(e: Dictionary, damage: float) -> void:
	e.hp -= damage
	e.flash = .20
	e.stun = .19
	_tone(155,.11,.45,-90)
	for i in 9: _spark(e.pos+Vector3(0,1,0),Color("cf93aa") if e.guardian else Color("84d9e1"),.55)
	if e.hp <= 0:
		e.alive = false
		kills += 1
		e.node.queue_free()
		player.hp = minf(player.max_hp,player.hp+player.leech)
		var soul := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = .21
		mesh.height = .42
		soul.mesh = mesh
		soul.material_override = _make_material(Color("f7c674"),.2,Color("f2a95d"))
		actors.add_child(soul)
		soul.position = e.pos+Vector3(0,.7,0)
		souls.append({"node":soul,"pos":e.pos,"value":20 if e.guardian else 11,"phase":rng.randf()*TAU})
		for i in 17: _spark(e.pos+Vector3(0,1,0),Color("edaa76"),.8)

func _hurt(amount: float) -> void:
	if player.invulnerable > 0 or mode != "playing": return
	player.hp -= amount*(1.0-player.armor)
	player.invulnerable = .65
	_tone(110,.26,.7,-75)
	screen_flash.color = Color(1,.14,.12,.23)
	for i in 18: _spark(player.pos+Vector3(0,1,0),Color("fb6d61"),.8)
	if player.hp <= 0:
		player.hp = 0.0
		mode = "dead"
		_show_death()

func _update_souls(dt: float) -> void:
	for soul in souls.duplicate():
		soul.phase += dt*5
		var distance: float = soul.pos.distance_to(player.pos)
		if distance < player.magnet:
			soul.pos = soul.pos.move_toward(player.pos,dt*(7.0+3.0*(player.magnet-distance)))
		if distance < .65:
			_gain_xp(soul.value)
			soul.node.queue_free()
			souls.erase(soul)
			continue
		soul.node.position = soul.pos+Vector3(0,.8+sin(soul.phase)*.16,0)

func _gain_xp(value: int) -> void:
	player.xp += value
	if player.xp >= player.xp_need:
		player.xp -= player.xp_need
		player.level += 1
		player.xp_need = roundi(player.xp_need*1.3+10)
		player.hp = minf(player.max_hp,player.hp+12)
		_tone(600,.3,.22,380)
		_open_blessings()

func _spark(pos: Vector3, color: Color, life: float) -> void:
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE*rng.randf_range(.07,.17)
	mesh.mesh = cube
	mesh.material_override = _make_material(color,.5,color)
	mesh.position = pos
	actors.add_child(mesh)
	effects.append({"node":mesh,"time":life,"max":life,"kind":"spark","velocity":Vector3(rng.randf_range(-4,4),rng.randf_range(1,5),rng.randf_range(-4,4))})

func _update_effects(dt: float) -> void:
	for effect in effects.duplicate():
		effect.time -= dt
		if effect.time <= 0:
			effect.node.queue_free()
			effects.erase(effect)
			continue
		if effect.kind == "spark":
			effect.node.position += effect.velocity*dt
			effect.velocity.y -= dt*12
			effect.node.scale = Vector3.ONE * effect.time/effect.max
		else: effect.node.light_energy = 3.7*effect.time/effect.max
	screen_flash.color.a = maxf(0.0,screen_flash.color.a-dt*.95)

func _update_camera(dt: float) -> void:
	var desired: Vector3 = player.pos+Vector3(13,18,16)
	camera.position = camera.position.lerp(desired,minf(1.0,dt*6.0))
	camera.look_at(player.pos+Vector3(0,1,0))

func _use_shrine() -> void:
	if mode != "playing": return
	var room: Dictionary = _room(current_room)
	var center := Vector3(current_room.x*ROOM_SIZE,0,current_room.y*ROOM_SIZE)
	if not room.shrine or room.shrine_used or player.pos.distance_to(center) > 3.7: return
	room.shrine_used = true
	player.hp = minf(player.max_hp,player.hp+maxf(35,player.max_hp*.38))
	_tone(490,.4,.16,300)
	for i in 35: _spark(center+Vector3(0,1.2,0),PALETTES[room.biome].light,1.1)
	_toast("THE SHRINE RESTORES YOU")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE: _dash()
		elif event.keycode == KEY_E: _use_shrine()
		elif event.keycode == KEY_ESCAPE:
			if mode == "playing": _show_pause()
			elif mode == "paused": _resume()
		elif mode == "upgrade" and event.keycode >= KEY_1 and event.keycode <= KEY_3:
			_choose_blessing(event.keycode-KEY_1)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and mode == "playing": _strike()

func _create_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	hud_ui = Control.new()
	hud_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud_ui)
	var left := VBoxContainer.new()
	left.position = Vector2(30,27)
	left.custom_minimum_size = Vector2(253,0)
	left.add_theme_constant_override("separation",7)
	hud_ui.add_child(left)
	left.add_child(_label("❖  EMBERWAKE",24,Color("f4d9b3"),TITLE_FONT))
	left.add_child(_label("THE ENDLESS DESCENT",10,Color("ad8f77"),BODY_FONT))
	left.add_spacer(false)
	health_label = _label("VITALITY",11,Color("d0b9a8"),BODY_FONT)
	left.add_child(health_label)
	health_bar = _bar(Color("ea7762"))
	left.add_child(health_bar)
	xp_label = _label("SOULFIRE",11,Color("d4b997"),BODY_FONT)
	left.add_child(xp_label)
	xp_bar = _bar(Color("ecc37d"))
	left.add_child(xp_bar)
	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-285,30)
	right.custom_minimum_size = Vector2(255,0)
	hud_ui.add_child(right)
	room_label = _label("THE FIRST EMBER",17,Color("f2dcc0"),TITLE_FONT)
	room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(room_label)
	depth_label = _label("DEPTH 0",10,Color("c0a17e"),BODY_FONT)
	depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(depth_label)
	kill_label = _label("0 VANQUISHED",10,Color("a9a0a0"),BODY_FONT)
	kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(kill_label)
	mini_map = Control.new()
	mini_map.custom_minimum_size = Vector2(154,154)
	mini_map.size = Vector2(154,154)
	mini_map.position = Vector2(101,12)
	mini_map.draw.connect(_draw_minimap)
	right.add_child(mini_map)
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 25
	bottom.offset_right = -25
	bottom.offset_top = -40
	bottom.offset_bottom = -14
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation",25)
	hud_ui.add_child(bottom)
	for text in ["WASD  MOVE","MOUSE  AIM + STRIKE","SPACE  DASH","E  SHRINE","ESC  PAUSE"]:
		bottom.add_child(_label(text,11,Color("c9b59d"),BODY_FONT))
	dash_label = _label("DASH READY",10,Color("f0bd80"),BODY_FONT)
	bottom.add_child(dash_label)
	message_label = _label("",25,Color("f3ce96"),TITLE_FONT)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	message_label.position = Vector2(-290,155)
	message_label.size = Vector2(580,50)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.hide()
	hud_ui.add_child(message_label)
	tip_label = _label("",13,Color("f0d59d"),BODY_FONT)
	tip_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	tip_label.position = Vector2(-160,-120)
	tip_label.size = Vector2(320,35)
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_ui.add_child(tip_label)
	screen_flash = ColorRect.new()
	screen_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_flash.color = Color(1,.14,.12,0)
	ui.add_child(screen_flash)
	menu_ui = Control.new()
	menu_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu_ui)
	overlay_ui = Control.new()
	overlay_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay_ui)
	# Hidden until a blessing or pause panel opens; while visible it takes clicks meant for the menu below it.
	overlay_ui.hide()

func _label(value: String, size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	label.add_theme_color_override("font_shadow_color",Color(0,0,0,.85))
	label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",3)
	return label

func _bar(fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(253,10)
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("171b25")
	bg.border_color = Color("685549")
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	bar.add_theme_stylebox_override("background",bg)
	bar.add_theme_stylebox_override("fill",fg)
	bar.max_value = 100
	bar.value = 100
	return bar

func _overlay_panel(parent: Control, width: float, height: float) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color("080a11e8")
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width,height)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-width/2,-height/2)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171923f4")
	style.border_color = Color("a67b56")
	style.set_border_width_all(2)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation",18)
	panel.add_child(box)
	return box

func _centered(label: Label) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(285,52)
	button.add_theme_font_override("font",BODY_FONT)
	button.add_theme_font_size_override("font_size",13)
	button.add_theme_color_override("font_color",Color("241a17"))
	button.add_theme_color_override("font_hover_color",Color("1a1617"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("dfac70")
	style.border_color = Color("f7d4a4")
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	var hover := style.duplicate()
	hover.bg_color = Color("f4cb8f")
	button.add_theme_stylebox_override("normal",style)
	button.add_theme_stylebox_override("hover",hover)
	button.pressed.connect(action)
	return button

func _show_menu() -> void:
	hud_ui.hide()
	menu_ui.show()
	for child in menu_ui.get_children(): child.queue_free()
	var box := _overlay_panel(menu_ui,650,530)
	box.add_child(_centered(_label("AN ENDLESS DESCENT",12,Color("c99d71"),BODY_FONT)))
	box.add_child(_centered(_label("❖",75,Color("f0aa64"),TITLE_FONT)))
	box.add_child(_centered(_label("EMBERWAKE",66,Color("f3dbb9"),TITLE_FONT)))
	box.add_child(_centered(_label("The light fades. The labyrinth does not.",16,Color("bfb1a5"),TITLE_FONT)))
	var start := _button("BEGIN THE DESCENT   ↗",_start_run)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(start)
	box.add_child(_centered(_label("Forge your path through an infinite, shifting crypt.",14,Color("b4aaa2"),BODY_FONT)))
	box.add_child(_centered(_label("WASD · MOVE     MOUSE · STRIKE     SPACE · DASH",11,Color("bba385"),BODY_FONT)))

func _open_blessings() -> void:
	mode = "upgrade"
	for child in overlay_ui.get_children(): child.queue_free()
	var box := _overlay_panel(overlay_ui,810,480)
	box.add_child(_centered(_label("THE FLAME GROWS BRIGHTER",12,Color("d7a16b"),BODY_FONT)))
	box.add_child(_centered(_label("Choose your blessing",40,Color("f1dbb6"),TITLE_FONT)))
	box.add_child(_centered(_label("The darkness yields a fragment of its power.",14,Color("aaa29c"),BODY_FONT)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	box.add_child(row)
	chosen_blessings.clear()
	var pool := BLESSINGS.duplicate()
	for i in 3:
		var choice: Dictionary = pool.pop_at(rng.randi_range(0,pool.size()-1))
		chosen_blessings.append(choice)
		var card := Button.new()
		card.custom_minimum_size = Vector2(235,202)
		card.text = "%s\n\n%s\n\n%s\n\n[ %d ]" % [choice.icon,choice.name,choice.desc,i+1]
		card.add_theme_font_override("font",BODY_FONT)
		card.add_theme_font_size_override("font_size",15)
		card.add_theme_color_override("font_color",Color("e9d7bc"))
		var style := StyleBoxFlat.new()
		style.bg_color = Color("272732")
		style.border_color = Color("705c50")
		style.set_border_width_all(1)
		style.set_content_margin_all(14)
		var hover := style.duplicate()
		hover.border_color = Color("ecbc83")
		hover.bg_color = Color("36313a")
		card.add_theme_stylebox_override("normal",style)
		card.add_theme_stylebox_override("hover",hover)
		card.pressed.connect(_choose_blessing.bind(i))
		row.add_child(card)
	box.add_child(_centered(_label("CHOOSE WITH MOUSE OR KEYS  1 · 2 · 3",11,Color("9d8a78"),BODY_FONT)))
	overlay_ui.show()

func _choose_blessing(index: int) -> void:
	if mode != "upgrade" or index < 0 or index >= chosen_blessings.size(): return
	var choice: Dictionary = chosen_blessings[index]
	match choice.stat:
		"damage": player.damage *= 1.25
		"speed": player.speed *= 1.15
		"health":
			player.max_hp += 30
			player.hp = minf(player.max_hp,player.hp+30)
		"range":
			player.range += .65
			player.arc += .15
		"attack": player.attack_delay *= .82
		"armor": player.armor = minf(.65,player.armor+.15)
		"magnet": player.magnet += 2.7
		"leech": player.leech += 3
		"dash": player.dash_delay *= .8
	mode = "playing"
	overlay_ui.hide()
	_tone(700,.2,.22,280)
	_toast(choice.name)

func _show_pause() -> void:
	mode = "paused"
	for child in overlay_ui.get_children(): child.queue_free()
	var box := _overlay_panel(overlay_ui,460,315)
	box.add_child(_centered(_label("A MOMENT IN THE DARK",11,Color("c6a17d"),BODY_FONT)))
	box.add_child(_centered(_label("Paused",49,Color("f0d7b3"),TITLE_FONT)))
	box.add_child(_centered(_label("The labyrinth waits for no one.",14,Color("aba29d"),BODY_FONT)))
	var resume := _button("CONTINUE   ↗",_resume)
	resume.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(resume)
	overlay_ui.show()

func _resume() -> void:
	mode = "playing"
	overlay_ui.hide()

func _show_death() -> void:
	for child in overlay_ui.get_children(): child.queue_free()
	var box := _overlay_panel(overlay_ui,510,365)
	box.add_child(_centered(_label("THE EMBER GOES QUIET",11,Color("c59b7c"),BODY_FONT)))
	box.add_child(_centered(_label("Into the dark",46,Color("edbd9a"),TITLE_FONT)))
	box.add_child(_centered(_label("DEPTH %d    ·    %d VANQUISHED    ·    LEVEL %d" % [abs(current_room.x)+abs(current_room.y),kills,player.level],14,Color("d2b99b"),BODY_FONT)))
	var retry := _button("RISE AGAIN   ↗",_start_run)
	retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(retry)
	box.add_child(_centered(_label("THE LABYRINTH WILL NEVER BE THE SAME",10,Color("8d8078"),BODY_FONT)))
	overlay_ui.show()

func _toast(text: String) -> void:
	message_label.text = text
	message_label.modulate.a = 1.0
	message_label.show()
	toast_time = 2.6

func _update_hud() -> void:
	health_label.text = "VITALITY                                  %d / %d" % [ceili(player.hp),roundi(player.max_hp)]
	health_bar.value = 100.0*player.hp/player.max_hp
	xp_label.text = "SOULFIRE  ·  LEVEL %d                    %d / %d" % [player.level,player.xp,player.xp_need]
	xp_bar.value = 100.0*player.xp/player.xp_need
	var room: Dictionary = _room(current_room)
	room_label.text = "THE FIRST EMBER" if room.depth == 0 else PALETTES[room.biome].name
	depth_label.text = "DEPTH %d" % room.depth
	kill_label.text = "%d VANQUISHED" % kills
	dash_label.text = "DASH READY" if player.dash_cd <= 0 else "DASH %.1fs" % player.dash_cd
	tip_label.text = "[ E ]   RESTORE AT SHRINE" if room.shrine and not room.shrine_used and player.pos.distance_to(Vector3(current_room.x*ROOM_SIZE,0,current_room.y*ROOM_SIZE)) < 4 else ""
	mini_map.queue_redraw()

func _draw_minimap() -> void:
	mini_map.draw_rect(Rect2(0,0,154,154),Color("0b0e16e8"))
	mini_map.draw_rect(Rect2(0,0,154,154),Color("8f7458"),false,1)
	for dz in range(-3,4):
		for dx in range(-3,4):
			var coord: Vector2i = current_room+Vector2i(dx,dz)
			if not rooms.has(coord) or not rooms[coord].seen: continue
			var room: Dictionary = rooms[coord]
			var pos := Vector2(77+dx*21,77+dz*21)
			mini_map.draw_rect(Rect2(pos-Vector2(8,8),Vector2(16,16)),PALETTES[room.biome].trim.darkened(.12))
			if room.shrine and not room.shrine_used: mini_map.draw_circle(pos,2,Color("f4d397"))
	mini_map.draw_circle(Vector2(77,77),4,Color("ffe0a2"))

## Stable observation/action interface for a local Open-Jev decision harness.
func agent_observe() -> Dictionary:
	if mode == "menu": return {"mode":mode}
	var nearby: Array = []
	for e in enemies:
		if e.alive and e.pos.distance_to(player.pos) < 16:
			nearby.append({"x":e.pos.x,"z":e.pos.z,"hp":e.hp,"guardian":e.guardian})
	var room: Dictionary = _room(current_room)
	var blockers := {}
	for action in ["N","NE","E","SE","S","SW","W","NW"]:
		var v: Vector3 = _direction_for(action)
		blockers[action] = _solid(player.pos+v*2.4)
	var unexplored: Array[String] = []
	for card in ["N","E","S","W"]:
		var v: Vector3 = _direction_for(card)
		var neighbor := current_room+Vector2i(roundi(v.x),roundi(v.z))
		if not _room(neighbor).seen: unexplored.append(card)
	return {"mode":mode,"seed":seed,"x":player.pos.x,"z":player.pos.z,"hp":player.hp,"max_hp":player.max_hp,
		"level":player.level,"xp":player.xp,"dash_ready":player.dash_cd <= 0,"depth":room.depth,"kills":kills,
		"room_x":current_room.x,"room_z":current_room.y,"local_x":player.pos.x-current_room.x*ROOM_SIZE,
		"local_z":player.pos.z-current_room.y*ROOM_SIZE,"unexplored_exits":unexplored,
		"enemies":nearby,"shrine":room.shrine and not room.shrine_used,
		"blocked":blockers,"blessings":chosen_blessings.map(func(c): return c.name) if mode == "upgrade" else []}

func agent_act(action: Dictionary) -> void:
	if mode == "menu":
		if action.get("start",false): _start_run()
		return
	if mode == "dead":
		if action.get("restart",false): _start_run()
		return
	if mode == "upgrade":
		if action.has("upgrade"): _choose_blessing(int(action.upgrade))
		return
	if mode != "playing": return
	agent_move = _direction_for(str(action.get("move","")))
	if action.has("aim_x") and action.has("aim_z"):
		agent_aim = Vector3(float(action.aim_x),0,float(action.aim_z)).normalized()
	elif agent_move.length() > 0:
		agent_aim = agent_move
	if agent_aim.length() > 0: player.facing = agent_aim
	if action.get("attack",false): _strike()
	if action.get("dash",false): _dash()
	if action.get("interact",false): _use_shrine()

func _direction_for(name: String) -> Vector3:
	match name.to_upper():
		"N": return Vector3(0,0,-1)
		"NE": return Vector3(1,0,-1).normalized()
		"E": return Vector3(1,0,0)
		"SE": return Vector3(1,0,1).normalized()
		"S": return Vector3(0,0,1)
		"SW": return Vector3(-1,0,1).normalized()
		"W": return Vector3(-1,0,0)
		"NW": return Vector3(-1,0,-1).normalized()
	return Vector3.ZERO

func _poll_agent(delta: float) -> void:
	if agent_server == null: return
	if agent_peer == null and agent_server.is_connection_available():
		agent_peer = agent_server.take_connection()
		agent_enabled = true
		agent_waiting = false
		agent_timer = 0
		_start_run()
		print("EMBERWAKE AGENT BRIDGE connected")
	if agent_peer == null: return
	agent_peer.poll()
	if agent_peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		agent_peer = null
		agent_enabled = false
		agent_waiting = false
		agent_move = Vector3.ZERO
		print("EMBERWAKE AGENT BRIDGE disconnected")
		return
	var available: int = agent_peer.get_available_bytes()
	if available > 0:
		var incoming: String = agent_peer.get_utf8_string(available)
		agent_buffer += incoming
		while "\n" in agent_buffer:
			var split: int = agent_buffer.find("\n")
			var line: String = agent_buffer.substr(0,split)
			agent_buffer = agent_buffer.substr(split+1)
			var parsed: Variant = JSON.parse_string(line)
			if parsed is Dictionary:
				agent_waiting = false
				agent_timer = .38
				agent_act(parsed)
	if not agent_waiting:
		agent_timer -= delta
		if agent_timer <= 0:
			agent_move = Vector3.ZERO
			agent_waiting = true
			var message: String = JSON.stringify(agent_observe())+"\n"
			agent_peer.put_data(message.to_utf8_buffer())
