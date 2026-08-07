extends CharacterBody3D
## Rehén controlado por un jugador. Cada cliente tiene autoridad sobre su propio
## cuerpo (movimiento y cámara); el servidor decide capturas, rescates y escapes.

enum State { FREE, CAPTURED, ESCAPED }

const WALK_SPEED := 3.2
const RUN_SPEED := 6.0
const CROUCH_SPEED := 1.6
const ACCEL := 12.0
const GRAVITY := 24.0
const MOUSE_SENS := 0.0025
const PITCH_MIN := deg_to_rad(-60.0)
const PITCH_MAX := deg_to_rad(35.0)
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.0

# Ruido: [intervalo entre pulsos, radio en metros]
const NOISE_RUN := [0.35, 15.0]
const NOISE_WALK := [0.7, 6.0]

@export var sync_body_rotation := 0.0
@export var sync_state: int = State.FREE
@export var sync_bottles := 0
## Animación que está reproduciendo. Se replica para que los demás jugadores te
## vean andar, correr o agacharte, en vez de deslizarte tieso por el suelo.
@export var sync_anim := ""

var crouching := false
var hidden_in: Node = null
var interact_target: Node = null
var hold_progress := 0.0
var _holding_continuous: Node = null
var _throw_cooldown := 0.0

var _noise_timer := 0.0
var _look_pitch := 0.0
var _target_height := STAND_HEIGHT

var modelo: ModeloPersonaje

@onready var body: Node3D = $Body
@onready var cam_pivot: Node3D = $CamPivot
@onready var spring_arm: SpringArm3D = $CamPivot/SpringArm
@onready var camera: Camera3D = $CamPivot/SpringArm/Camera
@onready var name_tag: Label3D = $NameTag
@onready var collision: CollisionShape3D = $Collision
@onready var interactor: Area3D = $Interactor


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	add_to_group("players")
	var peer_id := name.to_int()
	var color: Color = GameState.player_color(peer_id)

	# Cada jugador recibe un personaje distinto de la lista, según su hueco en
	# la partida, para poder distinguirse de un vistazo.
	modelo = ModeloPersonaje.new()
	modelo.name = "Modelo"
	body.add_child(modelo)
	modelo.montar(ModeloPersonaje.REHENES[_indice_en_partida() % ModeloPersonaje.REHENES.size()])
	modelo.tintar(color)

	name_tag.text = GameState.player_name(peer_id)
	name_tag.modulate = color

	var is_mine := is_multiplayer_authority()
	camera.current = is_mine
	name_tag.visible = not is_mine
	if is_mine:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameState.players_changed.connect(_refresh_visuals)


## Posición de este jugador en la lista de la partida (0, 1, 2...). Sirve para
## repartir los modelos de personaje sin que se repitan.
func _indice_en_partida() -> int:
	var i := 0
	for pid in GameState.players:
		if pid == peer_id():
			return i
		i += 1
	return 0


func peer_id() -> int:
	return name.to_int()


func is_free() -> bool:
	return sync_state == State.FREE


func _refresh_visuals() -> void:
	if is_instance_valid(name_tag) and not is_multiplayer_authority():
		name_tag.text = GameState.player_name(peer_id())


## El giro de cámara va en _input y no en _unhandled_input a propósito: con el
## ratón capturado el puntero queda clavado en el centro de la pantalla, así que
## cualquier elemento del HUD que haya ahí (la mira, sin ir más lejos) se quedaba
## con el movimiento y la cámara no giraba. Aquí llega antes que la interfaz.
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_pivot.rotate_y(-event.relative.x * MOUSE_SENS)
		_look_pitch = clampf(_look_pitch - event.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
		spring_arm.rotation.x = _look_pitch


## Los clics y el Esc se quedan aquí para que la interfaz tenga prioridad: si el
## clic se atendiera en _input, al pulsar los botones de la pantalla final el
## juego volvería a capturar el ratón y esos botones no funcionarían.
func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not GameState.online():
		return   # el anfitrión cerró: este nodo desaparece en cuanto cambie la escena
	if not is_multiplayer_authority():
		body.rotation.y = lerp_angle(body.rotation.y, sync_body_rotation, 12.0 * delta)
		_apply_remote_visuals()
		# Los demás jugadores reproducen la animación que les llega por red.
		if modelo != null and sync_anim != "":
			modelo.reproducir(sync_anim)
			modelo.agachar(sync_anim == ModeloPersonaje.AGACHADO_QUIETO or crouching)
		return

	var locked := sync_state != State.FREE or hidden_in != null
	var input_dir := Vector2.ZERO
	if not locked and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	crouching = not locked and Input.is_action_pressed("crouch")
	var want_run := not locked and not crouching and Input.is_action_pressed("run") and input_dir.length() > 0.1

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif want_run:
		speed = RUN_SPEED

	var basis_dir := Vector3.ZERO
	if input_dir.length() > 0.05:
		var yaw := cam_pivot.global_rotation.y
		basis_dir = (Vector3(input_dir.x, 0, input_dir.y).rotated(Vector3.UP, yaw)).normalized()

	var target_vel := basis_dir * speed
	velocity.x = move_toward(velocity.x, target_vel.x, ACCEL * delta * (speed + 2.0))
	velocity.z = move_toward(velocity.z, target_vel.z, ACCEL * delta * (speed + 2.0))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	if basis_dir.length() > 0.05:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-basis_dir.x, -basis_dir.z), 12.0 * delta)
	sync_body_rotation = body.rotation.y

	_update_crouch_shape(delta)
	_update_animacion(want_run)
	_update_noise(delta, want_run, basis_dir.length() > 0.05)
	_update_interaction(delta)
	_update_throw(delta)


## Elige la animación según lo que esté haciendo el personaje y la publica para
## que el resto de jugadores vean lo mismo.
func _update_animacion(corriendo: bool) -> void:
	if modelo == null:
		return
	if sync_state == State.CAPTURED:
		modelo.reproducir(ModeloPersonaje.CAER)
		modelo.agachar(false)
	else:
		var plana := Vector2(velocity.x, velocity.z).length()
		modelo.animar_movimiento(plana, corriendo, crouching)
		modelo.agachar(crouching)
	sync_anim = modelo.animacion_actual()


func _update_throw(delta: float) -> void:
	_throw_cooldown = maxf(0.0, _throw_cooldown - delta)
	if sync_state != State.FREE or hidden_in != null or sync_bottles <= 0 or _throw_cooldown > 0.0:
		return
	if not Input.is_action_just_pressed("throw"):
		return
	_throw_cooldown = 0.6
	var origin := global_position + Vector3.UP * 1.4
	var dir := -camera.global_transform.basis.z
	var level := get_tree().get_first_node_in_group("level")
	if level != null:
		level.request_throw.rpc_id(1, peer_id(), origin, dir)


func _apply_remote_visuals() -> void:
	var invisible := sync_state == State.ESCAPED
	body.visible = not invisible
	name_tag.visible = not invisible


func _update_crouch_shape(delta: float) -> void:
	_target_height = CROUCH_HEIGHT if crouching else STAND_HEIGHT
	var capsule: CapsuleShape3D = collision.shape
	capsule.height = move_toward(capsule.height, _target_height, 6.0 * delta)
	collision.position.y = capsule.height * 0.5
	# El modelo ya no se aplasta: se agacha con su propia pose (ModeloPersonaje).
	cam_pivot.position.y = 0.7 + capsule.height * 0.5


func _update_noise(delta: float, running: bool, moving: bool) -> void:
	if sync_state != State.FREE or crouching or not moving:
		_noise_timer = 0.0
		return
	var cfg: Array = NOISE_RUN if running else NOISE_WALK
	_noise_timer += delta
	if _noise_timer >= cfg[0]:
		_noise_timer = 0.0
		var level := get_tree().get_first_node_in_group("level")
		if level != null:
			level.report_noise.rpc_id(1, global_position, cfg[1])


# --- Interacción ---

func _update_interaction(delta: float) -> void:
	var best: Node = null
	var best_dist := INF
	for area in interactor.get_overlapping_areas():
		var it := area.get_parent()
		if it == null or not it.has_method("can_interact"):
			continue
		if not it.can_interact(self):
			continue
		if not Interaccion.hay_linea_de_vision(self, it):
			continue   # está al otro lado de un muro
		var d := global_position.distance_squared_to(area.global_position)
		if d < best_dist:
			best_dist = d
			best = it

	if best != interact_target:
		_stop_continuous()
		interact_target = best
		hold_progress = 0.0

	if interact_target == null:
		hold_progress = 0.0
		return

	var hold := float(interact_target.hold_time(self))
	if interact_target.is_continuous():
		# El servidor lleva la cuenta: solo le avisamos de empezar y soltar.
		var pressed := Input.is_action_pressed("interact")
		if pressed and _holding_continuous != interact_target:
			_holding_continuous = interact_target
			_send_hold(interact_target, true)
		elif not pressed and _holding_continuous == interact_target:
			_stop_continuous()
		hold_progress = clampf(interact_target.progress / maxf(hold, 0.01), 0.0, 1.0)
	elif hold <= 0.0:
		if Input.is_action_just_pressed("interact"):
			_request_interact(interact_target)
	else:
		if Input.is_action_pressed("interact"):
			hold_progress += delta / hold
			if hold_progress >= 1.0:
				hold_progress = 0.0
				_request_interact(interact_target)
		else:
			hold_progress = maxf(0.0, hold_progress - delta / hold)


func _stop_continuous() -> void:
	if _holding_continuous != null:
		if is_instance_valid(_holding_continuous):
			_send_hold(_holding_continuous, false)
		_holding_continuous = null


func _level() -> Node:
	return get_tree().get_first_node_in_group("level")


func _request_interact(target: Node) -> void:
	var level := _level()
	if level != null:
		level.request_interact.rpc_id(1, level.get_path_to(target), peer_id())


func _send_hold(target: Node, holding: bool) -> void:
	var level := _level()
	if level != null:
		level.request_hold.rpc_id(1, level.get_path_to(target), peer_id(), holding)


# --- Órdenes del servidor ---

@rpc("any_peer", "call_local", "reliable")
func net_teleport(pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	global_position = pos
	velocity = Vector3.ZERO


@rpc("any_peer", "call_local", "reliable")
func net_set_state(new_state: int) -> void:
	if multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	sync_state = new_state
	if new_state != State.FREE:
		hidden_in = null
		hold_progress = 0.0
		if is_multiplayer_authority():
			_stop_continuous()
	_apply_remote_visuals()


@rpc("any_peer", "call_local", "reliable")
func net_set_hidden(spot_path: NodePath) -> void:
	if multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	var level := get_tree().get_first_node_in_group("level")
	hidden_in = level.get_node_or_null(spot_path) if (level != null and not spot_path.is_empty()) else null
	if modelo != null:
		modelo.hacer_translucido(hidden_in != null)


@rpc("any_peer", "call_local", "reliable")
func net_set_bottles(count: int) -> void:
	if multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	sync_bottles = count
