extends Node3D
## Construye el complejo, coloca objetivos y arbitra la partida.
## Todas las decisiones (capturas, rescates, escapes) las toma el servidor.

signal local_player_spawned(player: Node)
signal round_started

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const GUARD_SCENE := preload("res://scenes/guard.tscn")
const BOTTLE_SCENE := preload("res://scenes/bottle.tscn")

const WALL_H := 3.4
const PERIMETER_H := 7.0
const WALL_T := 0.4
const READY_TIMEOUT := 6.0

const SPAWN_POINTS: Array[Vector3] = [
	Vector3(3, 0, 4), Vector3(6.5, 0, 4), Vector3(9, 0, 5.5), Vector3(3, 0, 9),
	Vector3(6.5, 0, 9), Vector3(9, 0, 13), Vector3(3, 0, 15), Vector3(6.5, 0, 18),
]
const PRISON_POINTS: Array[Vector3] = [
	Vector3(3, 0, 27), Vector3(6.5, 0, 27), Vector3(9, 0, 28), Vector3(3, 0, 32),
	Vector3(6.5, 0, 32), Vector3(9, 0, 36), Vector3(3, 0, 39), Vector3(6.5, 0, 42),
]
const BRONZE_KEY_SPOTS: Array[Vector3] = [
	Vector3(20, 0, 36), Vector3(26.5, 0, 42), Vector3(19, 0, 43.5), Vector3(27, 0, 34),
]
const KEYCARD_SPOTS: Array[Vector3] = [
	Vector3(20, 0, 5), Vector3(26.5, 0, 4), Vector3(19, 0, 12), Vector3(26.5, 0, 11),
]
const BOTTLE_SPOTS: Array[Vector3] = [
	Vector3(18.5, 0, 33.5), Vector3(27.5, 0, 34.5), Vector3(22, 0, 44),
	Vector3(13.5, 0, 6), Vector3(15.5, 0, 40), Vector3(31, 0, 19),
]
## label, posición, tamaño, rotación en grados
const HIDING_SPOTS := [
	["Armario", Vector3(13.2, 0, 14), Vector3(1.0, 2.0, 0.9), 90.0],
	["Armario", Vector3(13.2, 0, 30), Vector3(1.0, 2.0, 0.9), 90.0],
	["Taquilla", Vector3(18.2, 0, 2.5), Vector3(1.0, 2.0, 0.8), 90.0],
	["Escritorio", Vector3(27.5, 0, 13.5), Vector3(1.6, 1.0, 1.0), 0.0],
	["Caja", Vector3(18.5, 0, 39), Vector3(1.3, 1.4, 1.3), 0.0],
	["Caja", Vector3(27.8, 0, 44.5), Vector3(1.3, 1.4, 1.3), 0.0],
	["Contenedor", Vector3(30.5, 0, 9), Vector3(1.2, 1.8, 1.6), 0.0],
	["Contenedor", Vector3(41.5, 0, 27), Vector3(1.2, 1.8, 1.6), 0.0],
	["Barril", Vector3(46, 0, 8), Vector3(1.1, 1.6, 1.1), 0.0],
	["Barril", Vector3(60, 0, 40), Vector3(1.1, 1.6, 1.1), 0.0],
	["Caja", Vector3(30.5, 0, 44.5), Vector3(1.3, 1.4, 1.3), 0.0],
]
const PATROL_ROUTES := [
	[Vector3(14, 0, 5), Vector3(14, 0, 20), Vector3(14, 0, 41), Vector3(14, 0, 20)],
	[Vector3(23, 0, 7), Vector3(24, 0, 23), Vector3(23, 0, 40), Vector3(24, 0, 23)],
	[Vector3(36, 0, 6), Vector3(36, 0, 27), Vector3(36, 0, 40), Vector3(36, 0, 27)],
	[Vector3(47, 0, 7), Vector3(59, 0, 9), Vector3(59, 0, 38), Vector3(47, 0, 39)],
	[Vector3(53, 0, 23), Vector3(47, 0, 31), Vector3(58, 0, 23), Vector3(50, 0, 12)],
	[Vector3(31, 0, 3), Vector3(31, 0, 30), Vector3(40, 0, 30), Vector3(40, 0, 3)],
]

var _ready_peers := {}
var _round_started := false
var _ready_timer := 0.0
var _rng := RandomNumberGenerator.new()

@onready var nav_region: NavigationRegion3D = $Nav
@onready var players_node: Node3D = $Players
@onready var guards_node: Node3D = $Guards
@onready var items_node: Node3D = $Items
@onready var bottles_node: Node3D = $Bottles
@onready var interactables_node: Node3D = $Interactables
@onready var escape_zone: Area3D = $EscapeZone
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner


func _ready() -> void:
	add_to_group("level")
	players_node.child_entered_tree.connect(_on_players_child_entered)
	# La autoridad del jugador es su propio cliente, así que el servidor no puede
	# mandar su estado inicial por el sincronizador: va en los datos de spawn.
	player_spawner.spawn_function = _spawn_player
	_rng.seed = GameState.match_seed
	_build_world()
	_build_interactables()
	_bake_navigation()
	_spawn_guards()
	if multiplayer.is_server():
		# Puede que algún cliente ya avisara de que cargó el nivel antes que nosotros.
		_ready_peers = Network.scene_ready_peers().duplicate()
		_ready_peers[1] = true
		Network.peer_scene_ready.connect(_on_peer_scene_ready)
	_add_dev_runner()
	Network.notify_scene_ready()
	if multiplayer.is_server():
		_check_all_ready()


## Engancha el arnés de pruebas si se pidió por línea de comandos.
## Se carga con load() y no con preload() a propósito: el arnés se excluye al
## exportar el juego, y un preload de un archivo ausente rompe todo este script.
func _add_dev_runner() -> void:
	var pedido := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--sim" or arg == "--sim-guards" or arg.begins_with("--shot="):
			pedido = true
			break
	if not pedido:
		return
	const RUTA := "res://scripts/dev/sim_runner.gd"
	if not ResourceLoader.exists(RUTA):
		push_warning("El arnés de pruebas no está incluido en esta compilación.")
		return
	var guion: GDScript = load(RUTA)
	add_child(guion.new())


func _process(delta: float) -> void:
	if not GameState.online() or not multiplayer.is_server() or _round_started:
		return
	_ready_timer += delta
	if _ready_timer >= READY_TIMEOUT and not _ready_peers.is_empty():
		_start_round()


func _physics_process(_delta: float) -> void:
	if not GameState.online() or not multiplayer.is_server():
		return
	if _round_started and GameState.phase == GameState.Phase.PLAYING:
		_check_escapes()


# ---------------------------------------------------------------- construcción

func _mat(color: Color, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _box(parent: Node, center: Vector3, box_size: Vector3, mat: Material, solid := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	mi.mesh = bm
	mi.position = center
	mi.material_override = mat
	parent.add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box_size
		cs.shape = shape
		sb.add_child(cs)
		mi.add_child(sb)


func _wall(x1: float, z1: float, x2: float, z2: float, mat: Material, height := WALL_H) -> void:
	var center := Vector3((x1 + x2) * 0.5, height * 0.5, (z1 + z2) * 0.5)
	var box_size: Vector3
	if is_equal_approx(x1, x2):
		box_size = Vector3(WALL_T, height, absf(z2 - z1))
	else:
		box_size = Vector3(absf(x2 - x1), height, WALL_T)
	_box(nav_region, center, box_size, mat)


func _light(pos: Vector3, color: Color, energy: float, light_range: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	add_child(l)


func _build_world() -> void:
	var floor_mat := _mat(Color(0.22, 0.23, 0.26))
	var yard_mat := _mat(Color(0.17, 0.19, 0.18))
	var wall_mat := _mat(Color(0.36, 0.37, 0.40))
	var cell_mat := _mat(Color(0.30, 0.29, 0.33))

	# Suelos
	_box(nav_region, Vector3(21.5, -0.25, 23), Vector3(45, 0.5, 48), floor_mat)   # interior
	_box(nav_region, Vector3(53.5, -0.25, 23), Vector3(21, 0.5, 48), yard_mat)    # patio
	_box(nav_region, Vector3(68, -0.25, 23), Vector3(10, 0.5, 6), yard_mat)       # túnel de salida

	# Perímetro exterior, más alto: encierra el recinto y tapa el horizonte
	var fence_mat := _mat(Color(0.26, 0.27, 0.30))
	_wall(0, 0, 64, 0, fence_mat, PERIMETER_H)
	_wall(0, 46, 64, 46, fence_mat, PERIMETER_H)
	_wall(0, 0, 0, 46, fence_mat, PERIMETER_H)
	_wall(64, 0, 64, 20, fence_mat, PERIMETER_H)
	_wall(64, 26, 64, 46, fence_mat, PERIMETER_H)
	# Túnel de salida
	_wall(64, 20, 73, 20, fence_mat, PERIMETER_H)
	_wall(64, 26, 73, 26, fence_mat, PERIMETER_H)

	# Bloque de celdas (hueco en z 10..12 y z 33..35 para las rejas)
	_wall(11, 0, 11, 10, cell_mat)
	_wall(11, 12, 11, 33, cell_mat)
	_wall(11, 35, 11, 46, cell_mat)
	_wall(0, 23, 11, 23, cell_mat)

	# Muros divisorios con sus huecos de paso (z 21..25)
	for x in [17.0, 29.0, 43.0]:
		_wall(x, 0, x, 21, wall_mat)
		_wall(x, 25, x, 46, wall_mat)

	# Sala de guardias y almacén (hueco en x 22..26)
	for z in [15.0, 31.0]:
		_wall(17, z, 22, z, wall_mat)
		_wall(26, z, 29, z, wall_mat)

	# Sala del generador (hueco en x 34..38)
	_wall(29, 33, 34, 33, wall_mat)
	_wall(38, 33, 43, 33, wall_mat)

	# Mobiliario decorativo que además sirve de cobertura visual
	var prop_mat := _mat(Color(0.28, 0.30, 0.34))
	for spot in [
		[Vector3(21, 0.5, 8), Vector3(3.0, 1.0, 1.2)],      # mesa sala de guardias
		[Vector3(25, 0.9, 38), Vector3(1.2, 1.8, 4.0)],     # estantería almacén
		[Vector3(20, 0.9, 40), Vector3(1.2, 1.8, 3.0)],
		[Vector3(35, 1.1, 43), Vector3(4.5, 2.2, 1.6)],     # generador
		[Vector3(50, 0.7, 20), Vector3(2.0, 1.4, 6.0)],     # muro bajo del patio
		[Vector3(56, 0.7, 33), Vector3(6.0, 1.4, 2.0)],
	]:
		_box(nav_region, spot[0], spot[1], prop_mat)

	# Iluminación: pasillos y salas en penumbra, patio con focos fríos
	for p in [
		Vector3(5, 3, 8), Vector3(5, 3, 36), Vector3(14, 3, 10), Vector3(14, 3, 24),
		Vector3(14, 3, 38), Vector3(23, 3, 7), Vector3(23, 3, 23), Vector3(23, 3, 39),
		Vector3(36, 3, 10), Vector3(36, 3, 26), Vector3(36, 3, 40),
	]:
		_light(p, Color(1.0, 0.86, 0.66), 2.4, 13.0)
	for p in [
		Vector3(46, 6, 8), Vector3(46, 6, 38), Vector3(56, 6, 14),
		Vector3(56, 6, 32), Vector3(61, 5, 23), Vector3(68, 4, 23),
	]:
		_light(p, Color(0.72, 0.84, 1.0), 5.5, 26.0)


func _build_interactables() -> void:
	# Rejas de las celdas
	var north_gate := CellGate.new()
	north_gate.name = "NorthCellGate"
	north_gate.mode = "escape"
	north_gate.position = Vector3(11, 0, 11)
	interactables_node.add_child(north_gate)

	var south_gate := CellGate.new()
	south_gate.name = "SouthCellGate"
	south_gate.mode = "rescue"
	south_gate.position = Vector3(11, 0, 34)
	interactables_node.add_child(south_gate)

	# Puertas con llave
	var cell_door := LockedDoor.new()
	cell_door.name = "CellBlockDoor"
	cell_door.requires = "bronze_key_found"
	cell_door.requires_label = "la llave de bronce"
	cell_door.door_label = "Puerta del bloque"
	cell_door.door_size = Vector3(0.45, 3.2, 4.0)
	cell_door.position = Vector3(17, 0, 23)
	interactables_node.add_child(cell_door)

	var security_door := LockedDoor.new()
	security_door.name = "SecurityDoor"
	security_door.requires = "keycard_found"
	security_door.requires_label = "la tarjeta de seguridad"
	security_door.door_label = "Puerta de seguridad"
	security_door.door_size = Vector3(0.45, 3.2, 4.0)
	security_door.door_color = Color(0.24, 0.30, 0.36)
	security_door.position = Vector3(43, 0, 23)
	interactables_node.add_child(security_door)

	# Portón de salida
	var gate := ExitGate.new()
	gate.name = "ExitGate"
	gate.position = Vector3(64, 0, 23)
	interactables_node.add_child(gate)

	# Palancas del generador: hacen falta dos personas a la vez
	var lever_a := CoopLever.new()
	lever_a.name = "LeverA"
	lever_a.lever_label = "Palanca izquierda"
	lever_a.position = Vector3(31.5, 0, 40)
	interactables_node.add_child(lever_a)

	var lever_b := CoopLever.new()
	lever_b.name = "LeverB"
	lever_b.lever_label = "Palanca derecha"
	lever_b.position = Vector3(40.5, 0, 40)
	interactables_node.add_child(lever_b)

	lever_a.partner_path = lever_a.get_path_to(lever_b)
	lever_b.partner_path = lever_b.get_path_to(lever_a)

	# Escondites
	var idx := 0
	for spot in HIDING_SPOTS:
		var h := HidingSpot.new()
		h.name = "Hide%d" % idx
		h.spot_label = spot[0]
		h.position = spot[1]
		h.spot_size = spot[2]
		h.rotation.y = deg_to_rad(spot[3])
		interactables_node.add_child(h)
		idx += 1

	# Objetivos: la llave y la tarjeta cambian de sitio cada partida
	var key := ItemPickup.new()
	key.name = "BronzeKey"
	key.item_id = "bronze_key"
	key.item_label = "llave de bronce"
	key.flag = "bronze_key_found"
	key.item_color = Color(0.9, 0.6, 0.2)
	key.position = BRONZE_KEY_SPOTS[_rng.randi() % BRONZE_KEY_SPOTS.size()]
	items_node.add_child(key)

	var card := ItemPickup.new()
	card.name = "Keycard"
	card.item_id = "keycard"
	card.item_label = "tarjeta de seguridad"
	card.flag = "keycard_found"
	card.item_color = Color(0.2, 0.75, 1.0)
	card.position = KEYCARD_SPOTS[_rng.randi() % KEYCARD_SPOTS.size()]
	items_node.add_child(card)

	for i in BOTTLE_SPOTS.size():
		var b := ItemPickup.new()
		b.name = "Bottle%d" % i
		b.item_id = "bottle"
		b.item_label = "botella"
		b.item_color = Color(0.4, 0.85, 0.5)
		b.position = BOTTLE_SPOTS[i]
		items_node.add_child(b)


func _bake_navigation() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 1.75
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = 1
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav_region.navigation_mesh = nav_mesh
	nav_region.bake_navigation_mesh(false)


func _spawn_guards() -> void:
	var player_count: int = maxi(GameState.players.size(), 1)
	var count: int = clampi(2 + int(ceil(player_count / 2.0)), 3, PATROL_ROUTES.size())
	for i in count:
		var g := GUARD_SCENE.instantiate()
		g.name = "Guard%d" % i
		var route: Array = PATROL_ROUTES[i]
		g.waypoints = PackedVector3Array(route)
		g.position = route[0]
		guards_node.add_child(g)


# ------------------------------------------------------------ inicio de ronda

func _on_peer_scene_ready(id: int) -> void:
	_ready_peers[id] = true
	_check_all_ready()


func _check_all_ready() -> void:
	if _ready_peers.size() >= GameState.players.size():
		_start_round()


func _start_round() -> void:
	if _round_started:
		return
	_round_started = true
	round_started.emit()
	var i := 0
	for pid in GameState.players:
		player_spawner.spawn({"id": pid, "pos": SPAWN_POINTS[i % SPAWN_POINTS.size()]})
		i += 1
	GameState.net_message.rpc("Están encerrados. Fuercen la reja y salgan sin que los vean.")


func _spawn_player(data: Dictionary) -> Node:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(data["id"])
	p.position = data["pos"]
	return p


func _on_players_child_entered(node: Node) -> void:
	if node.name.to_int() == GameState.local_id():
		local_player_spawned.emit(node)


func find_player(pid: int) -> Node:
	return players_node.get_node_or_null(str(pid))


# ------------------------------------------------------------------- ruido/IA

@rpc("any_peer", "call_local", "unreliable")
func report_noise(pos: Vector3, radius: float) -> void:
	if multiplayer.is_server():
		server_noise(pos, radius)


func server_noise(pos: Vector3, radius: float) -> void:
	for g in guards_node.get_children():
		if g.global_position.distance_to(pos) <= radius:
			g.alert_to(pos)


func on_guard_spotted(pid: int) -> void:
	if not multiplayer.is_server():
		return
	GameState.net_message.rpc("¡Han visto a %s!" % GameState.player_name(pid))


func on_power_cut() -> void:
	if not multiplayer.is_server() or GameState.power_off:
		return
	GameState.net_set_objective.rpc("power_off", true)
	GameState.net_message.rpc("Corriente cortada. El portón ya se puede abrir.")


# -------------------------------------------------------------- interacciones

@rpc("any_peer", "call_local", "reliable")
func request_interact(target_path: NodePath, pid: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != pid:
		return
	var target := get_node_or_null(target_path)
	var player := find_player(pid)
	if target == null or player == null or not target.has_method("server_interact"):
		return
	if player.global_position.distance_to(target.global_position) > 4.0:
		return
	if not target.can_interact(player):
		return
	target.server_interact(player)


@rpc("any_peer", "call_local", "reliable")
func request_hold(target_path: NodePath, pid: int, holding: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != pid:
		return
	var target := get_node_or_null(target_path)
	var player := find_player(pid)
	if target == null or player == null or not target.has_method("server_hold"):
		return
	if holding and (player.global_position.distance_to(target.global_position) > 4.0 or not target.can_interact(player)):
		return
	target.server_hold(player, holding)


@rpc("any_peer", "call_local", "reliable")
func request_throw(pid: int, origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != pid:
		return
	var player := find_player(pid)
	if player == null or player.sync_bottles <= 0 or not player.is_free():
		return
	player.net_set_bottles.rpc(player.sync_bottles - 1)
	var b := BOTTLE_SCENE.instantiate()
	b.position = origin + dir.normalized() * 0.6
	bottles_node.add_child(b)
	b.linear_velocity = dir.normalized() * 14.0 + Vector3.UP * 2.0


# --------------------------------------------------------- capturas y escapes

func capture_player(pid: int) -> void:
	if not multiplayer.is_server() or GameState.is_captured(pid) or GameState.is_escaped(pid):
		return
	var player := find_player(pid)
	if player == null:
		return
	GameState.net_set_player_flag.rpc(pid, "captured", true)
	player.net_set_state.rpc(player.State.CAPTURED)
	var idx: int = GameState.captured_player_ids().size() - 1
	player.net_teleport.rpc(PRISON_POINTS[maxi(idx, 0) % PRISON_POINTS.size()])
	GameState.net_message.rpc("%s fue capturado. ¡Vayan a por él a la celda sur!" % GameState.player_name(pid))
	_check_round_over()


func free_captured_players(rescuer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var freed := 0
	var idx := 0
	for pid in GameState.captured_player_ids():
		var player := find_player(pid)
		if player == null:
			continue
		GameState.net_set_player_flag.rpc(pid, "captured", false)
		player.net_set_state.rpc(player.State.FREE)
		player.net_teleport.rpc(Vector3(13.5, 0, 34) + Vector3(0, 0, idx * 1.2))
		freed += 1
		idx += 1
	if freed > 0:
		GameState.net_message.rpc("%s liberó a %d compañero(s)." % [GameState.player_name(rescuer_id), freed])


func _check_escapes() -> void:
	for body in escape_zone.get_overlapping_bodies():
		if not body.is_in_group("players"):
			continue
		var pid: int = body.peer_id()
		if GameState.is_escaped(pid) or GameState.is_captured(pid):
			continue
		GameState.net_set_player_flag.rpc(pid, "escaped", true)
		body.net_set_state.rpc(body.State.ESCAPED)
		GameState.net_message.rpc("¡%s está fuera!" % GameState.player_name(pid))
		_check_round_over()


func on_player_left(pid: int) -> void:
	# Libera lo que estuviera ocupando, o quedaría bloqueado el resto de la ronda.
	for node in interactables_node.get_children():
		if node is HidingSpot and node.occupant == pid:
			node.net_set_occupant.rpc(0)
		elif node is CoopLever and node.held_by == pid:
			node.net_set_held.rpc(0)
	var p := find_player(pid)
	if p != null:
		p.queue_free()
	_check_round_over()


func _check_round_over() -> void:
	if not multiplayer.is_server() or GameState.phase != GameState.Phase.PLAYING:
		return
	if not GameState.free_player_ids().is_empty():
		return
	# Nadie queda libre: la ronda termina. Basta con que alguien saliera para ganar.
	var victory := GameState.escaped_count() > 0
	GameState.net_game_over.rpc(victory)
