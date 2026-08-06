extends CharacterBody3D
## Guardia controlado por IA. Solo el servidor decide su comportamiento;
## los clientes reciben la posición y el estado ya resueltos.

enum State { PATROL, SUSPICIOUS, CHASE, RETURN }

const PATROL_SPEED := 2.1
const SEARCH_SPEED := 3.2
const CHASE_SPEED := 5.5
const ACCEL := 10.0
const GRAVITY := 24.0

const VIEW_DISTANCE := 16.0
const VIEW_DISTANCE_ALERT := 21.0
const VIEW_ANGLE := deg_to_rad(52.0)      # medio ángulo del cono
const VIEW_ANGLE_ALERT := deg_to_rad(70.0)
const CATCH_DISTANCE := 1.7
const CLOSE_RANGE := 4.0                   # a bocajarro te ve aunque estés agachado
const SPOT_TIME := 1.1                     # segundos mirándote para detectarte
const LOSE_TIME := 4.0                     # segundos sin verte antes de rendirse
const SEARCH_TIME := 7.0

@export var sync_facing := 0.0
@export var sync_state: int = State.PATROL
@export var sync_awareness := 0.0

var waypoints: PackedVector3Array = PackedVector3Array()

var _wp_index := 0
var _wp_wait := 0.0
var _target_player: Node3D = null
var _lost_timer := 0.0
var _search_timer := 0.0
var _search_point := Vector3.ZERO
var _awareness := 0.0
var _repath := 0.0
var _cone_pulse := 0.0

@onready var body: Node3D = $Body
@onready var view_cone: MeshInstance3D = $Body/ViewCone
@onready var agent: NavigationAgent3D = $NavAgent
@onready var eye_cast: RayCast3D = $EyeCast


func _ready() -> void:
	add_to_group("guards")
	view_cone.mesh = _build_cone_mesh(VIEW_DISTANCE, VIEW_ANGLE)
	set_physics_process(true)


func _build_cone_mesh(dist: float, half_angle: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var steps := 18
	for i in steps:
		var a0 := -half_angle + (2.0 * half_angle) * (float(i) / steps)
		var a1 := -half_angle + (2.0 * half_angle) * (float(i + 1) / steps)
		verts.append(Vector3.ZERO)
		verts.append(Vector3(sin(a1), 0, -cos(a1)) * dist)
		verts.append(Vector3(sin(a0), 0, -cos(a0)) * dist)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _physics_process(delta: float) -> void:
	if not GameState.online():
		return   # el anfitrión cerró: este nodo desaparece en cuanto cambie la escena
	if not multiplayer.is_server():
		body.rotation.y = lerp_angle(body.rotation.y, sync_facing, 10.0 * delta)
		_update_cone_visual(delta)
		return

	match sync_state:
		State.PATROL:
			_tick_patrol(delta)
		State.SUSPICIOUS:
			_tick_suspicious(delta)
		State.CHASE:
			_tick_chase(delta)
		State.RETURN:
			_tick_return(delta)

	_perceive(delta)
	_move(delta)
	sync_facing = body.rotation.y
	sync_awareness = _awareness
	_update_cone_visual(delta)


# --- Percepción ---

func _perceive(delta: float) -> void:
	var seen: Node3D = null
	var best_score := 0.0
	var dist_limit := VIEW_DISTANCE_ALERT if GameState.alert else VIEW_DISTANCE
	var angle_limit := VIEW_ANGLE_ALERT if GameState.alert else VIEW_ANGLE

	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Node3D
		if p == null or not p.is_free() or p.hidden_in != null:
			continue
		var to: Vector3 = p.global_position - global_position
		var dist := to.length()
		if dist > dist_limit:
			continue
		var forward := -body.global_transform.basis.z
		var flat := Vector3(to.x, 0, to.z).normalized()
		var angle: float = absf(forward.signed_angle_to(flat, Vector3.UP))
		if angle > angle_limit and dist > CLOSE_RANGE:
			continue
		if not _has_line_of_sight(p):
			continue
		# Agacharse a media distancia te hace mucho más difícil de ver.
		var score := 1.0 - clampf(dist / dist_limit, 0.0, 0.9)
		if p.crouching and dist > CLOSE_RANGE:
			score *= 0.35
		if score > best_score:
			best_score = score
			seen = p

	if seen != null:
		_awareness = minf(1.0, _awareness + delta * (1.0 / SPOT_TIME) * (0.6 + best_score))
		if _awareness >= 1.0:
			_start_chase(seen)
		elif sync_state == State.PATROL and _awareness > 0.35:
			_search_point = seen.global_position
			_enter_suspicious(_search_point)
	else:
		_awareness = maxf(0.0, _awareness - delta * 0.5)
		if sync_state == State.CHASE:
			_lost_timer += delta
			if _lost_timer >= LOSE_TIME:
				_enter_suspicious(_search_point)


func _has_line_of_sight(target: Node3D) -> bool:
	eye_cast.global_position = global_position + Vector3.UP * 1.75
	var head_pos: Vector3 = target.global_position + Vector3.UP * (0.6 if target.crouching else 1.4)
	eye_cast.target_position = eye_cast.to_local(head_pos)
	eye_cast.force_raycast_update()
	return not eye_cast.is_colliding()


# --- Estados ---

func _tick_patrol(delta: float) -> void:
	if waypoints.is_empty():
		return
	if _wp_wait > 0.0:
		_wp_wait -= delta
		body.rotation.y += delta * 0.9   # mira alrededor mientras espera
		velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta * 6.0)
		velocity.z = move_toward(velocity.z, 0.0, ACCEL * delta * 6.0)
		return
	_set_target(waypoints[_wp_index])
	if global_position.distance_to(waypoints[_wp_index]) < 1.4:
		_wp_index = (_wp_index + 1) % waypoints.size()
		_wp_wait = randf_range(1.0, 2.5)


func _tick_suspicious(delta: float) -> void:
	_search_timer -= delta
	_set_target(_search_point)
	if global_position.distance_to(_search_point) < 1.5:
		body.rotation.y += delta * 1.6
	if _search_timer <= 0.0:
		sync_state = State.RETURN
		_recompute_alert()


func _tick_chase(_delta: float) -> void:
	if not is_instance_valid(_target_player) or not _target_player.is_free() or _target_player.hidden_in != null:
		_enter_suspicious(_search_point)
		return
	_search_point = _target_player.global_position
	_set_target(_search_point)
	if global_position.distance_to(_target_player.global_position) <= CATCH_DISTANCE:
		var level := get_tree().get_first_node_in_group("level")
		if level != null:
			level.capture_player(_target_player.peer_id())
		_enter_suspicious(global_position)


func _tick_return(_delta: float) -> void:
	if waypoints.is_empty():
		sync_state = State.PATROL
		return
	var nearest := 0
	var best := INF
	for i in waypoints.size():
		var d := global_position.distance_to(waypoints[i])
		if d < best:
			best = d
			nearest = i
	_wp_index = nearest
	_set_target(waypoints[nearest])
	if best < 1.6:
		sync_state = State.PATROL


func _start_chase(target: Node3D) -> void:
	_target_player = target
	_search_point = target.global_position
	_lost_timer = 0.0
	if sync_state != State.CHASE:
		sync_state = State.CHASE
		var level := get_tree().get_first_node_in_group("level")
		if level != null:
			level.on_guard_spotted(target.peer_id())
	_recompute_alert()


func _enter_suspicious(point: Vector3) -> void:
	sync_state = State.SUSPICIOUS
	_search_point = point
	_search_timer = SEARCH_TIME
	_lost_timer = 0.0
	_awareness = minf(_awareness, 0.6)
	_target_player = null
	_recompute_alert()


func alert_to(point: Vector3) -> void:
	## Llamado por el nivel cuando alguien hace ruido cerca.
	if sync_state == State.CHASE:
		return
	_enter_suspicious(point)


func _recompute_alert() -> void:
	if not multiplayer.is_server():
		return
	var any_chase := false
	for g in get_tree().get_nodes_in_group("guards"):
		if g.sync_state == State.CHASE:
			any_chase = true
			break
	if GameState.alert != any_chase:
		GameState.net_set_alert.rpc(any_chase)


# --- Movimiento ---

func _set_target(point: Vector3) -> void:
	_repath -= get_physics_process_delta_time()
	if _repath <= 0.0 or agent.target_position.distance_to(point) > 1.0:
		agent.target_position = point
		_repath = 0.25


func _move(delta: float) -> void:
	var speed := PATROL_SPEED
	match sync_state:
		State.SUSPICIOUS, State.RETURN:
			speed = SEARCH_SPEED
		State.CHASE:
			speed = CHASE_SPEED

	if not agent.is_navigation_finished():
		var next := agent.get_next_path_position()
		var dir := (next - global_position)
		dir.y = 0.0
		if dir.length() > 0.05:
			dir = dir.normalized()
			velocity.x = move_toward(velocity.x, dir.x * speed, ACCEL * delta * 6.0)
			velocity.z = move_toward(velocity.z, dir.z * speed, ACCEL * delta * 6.0)
			body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 7.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta * 6.0)
		velocity.z = move_toward(velocity.z, 0.0, ACCEL * delta * 6.0)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _update_cone_visual(delta: float) -> void:
	_cone_pulse += delta
	var mat: StandardMaterial3D = view_cone.material_override
	if mat == null:
		return
	match sync_state:
		State.CHASE:
			mat.albedo_color = Color(1.0, 0.25, 0.2, 0.22)
			mat.emission = Color(1.0, 0.25, 0.2)
		State.SUSPICIOUS:
			mat.albedo_color = Color(1.0, 0.65, 0.15, 0.18)
			mat.emission = Color(1.0, 0.65, 0.15)
		_:
			var a := 0.10 + sync_awareness * 0.12
			mat.albedo_color = Color(1.0, 0.88, 0.35, a)
			mat.emission = Color(1.0, 0.88, 0.35)
