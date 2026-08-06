class_name CoopLever
extends Interactable
## Palanca del generador. Hay dos y las dos deben mantenerse pulsadas
## a la vez por jugadores distintos: nadie puede hacerlo en solitario.

const HOLD_REQUIRED := 2.5

@export var lever_label := "Palanca"
@export var partner_path := NodePath()

var held_by := 0
var progress := 0.0
var done := false

var _handle: Node3D
var _lamp: OmniLight3D
var _lamp_mesh: MeshInstance3D
var _sync_timer := 0.0


func _build() -> void:
	interact_radius = 2.0
	add_box(Vector3(0.9, 1.1, 0.6), Vector3(0, 0.55, 0), Color(0.24, 0.26, 0.3))

	_handle = Node3D.new()
	_handle.name = "Handle"
	_handle.position = Vector3(0, 1.1, 0)
	add_child(_handle)
	var stick := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.05
	sm.bottom_radius = 0.06
	sm.height = 0.7
	stick.mesh = sm
	stick.position = Vector3(0, 0.35, 0)
	stick.material_override = Interactable.make_material(Color(0.8, 0.2, 0.15), 0.3)
	_handle.add_child(stick)

	_lamp_mesh = MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.12
	lm.height = 0.24
	_lamp_mesh.mesh = lm
	_lamp_mesh.position = Vector3(0.35, 1.25, 0)
	_lamp_mesh.material_override = Interactable.make_material(Color(0.6, 0.1, 0.1), 0.2, Color(0.8, 0.1, 0.1))
	add_child(_lamp_mesh)

	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.3, 0.2)
	_lamp.light_energy = 1.0
	_lamp.omni_range = 4.0
	_lamp.position = Vector3(0.35, 1.25, 0)
	add_child(_lamp)


func _partner() -> CoopLever:
	if partner_path.is_empty():
		return null
	var n := get_node_or_null(partner_path)
	return n as CoopLever


func can_interact(player: Node) -> bool:
	if done or GameState.power_off:
		return false
	return player.is_free() and (held_by == 0 or held_by == player.peer_id())


func get_prompt(_player: Node) -> String:
	var partner := _partner()
	if partner != null and partner.held_by == 0:
		return "%s — mantén pulsado (hace falta alguien en la otra palanca)" % lever_label
	return "%s — ¡mantén pulsado ahora!" % lever_label


func hold_time(_player: Node) -> float:
	return HOLD_REQUIRED


func is_continuous() -> bool:
	return true


func server_hold(player: Node, holding: bool) -> void:
	if done:
		return
	var pid: int = player.peer_id()
	if holding and held_by == 0:
		net_set_held.rpc(pid)
	elif not holding and held_by == pid:
		net_set_held.rpc(0)


func _physics_process(delta: float) -> void:
	var partner := _partner()
	var both := held_by != 0 and partner != null and partner.held_by != 0 and partner.held_by != held_by
	if is_instance_valid(_handle):
		_handle.rotation.x = lerp_angle(_handle.rotation.x, deg_to_rad(-45.0) if held_by != 0 else 0.0, 10.0 * delta)
	_update_lamp(both)

	if not multiplayer.is_server() or done:
		return
	# Solo la palanca "maestra" (la que tiene compañera) cuenta, para no duplicar.
	if partner == null or self.get_index() > partner.get_index():
		return
	if both:
		progress += delta
		if progress >= HOLD_REQUIRED:
			net_complete.rpc()
			var level := get_tree().get_first_node_in_group("level")
			if level != null:
				level.on_power_cut()
	else:
		progress = maxf(0.0, progress - delta * 1.5)
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = 0.15
		net_sync_progress.rpc(progress)


func _update_lamp(both: bool) -> void:
	if not is_instance_valid(_lamp):
		return
	var color := Color(1.0, 0.3, 0.2)
	if done or GameState.power_off:
		color = Color(0.25, 1.0, 0.35)
	elif both:
		color = Color(1.0, 0.85, 0.2)
	elif held_by != 0:
		color = Color(1.0, 0.6, 0.2)
	_lamp.light_color = color
	var mat: StandardMaterial3D = _lamp_mesh.material_override
	mat.albedo_color = color
	mat.emission = color


@rpc("authority", "call_local", "reliable")
func net_set_held(pid: int) -> void:
	held_by = pid


@rpc("authority", "call_local", "unreliable")
func net_sync_progress(value: float) -> void:
	progress = value
	var partner := _partner()
	if partner != null:
		partner.progress = value


@rpc("authority", "call_local", "reliable")
func net_complete() -> void:
	done = true
	progress = HOLD_REQUIRED
	var partner := _partner()
	if partner != null:
		partner.done = true
