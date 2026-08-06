class_name LockedDoor
extends Interactable
## Puerta que exige un objetivo del equipo (llave de bronce, tarjeta...).
## Una vez abierta se queda abierta para todos.

@export var requires := ""            # nombre de la bandera en GameState
@export var requires_label := "una llave"
@export var door_label := "Puerta"
@export var door_size := Vector3(0.45, 3.0, 4.0)
@export var door_color := Color(0.35, 0.28, 0.2)

var is_open := false
var _panel: Node3D
var _collision: CollisionShape3D


func _build() -> void:
	_panel = Node3D.new()
	_panel.name = "Panel"
	_panel.position = Vector3(0, door_size.y * 0.5, 0)
	add_child(_panel)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = door_size
	mi.mesh = bm
	mi.material_override = Interactable.make_material(door_color)
	_panel.add_child(mi)

	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = door_size
	cs.shape = shape
	sb.add_child(cs)
	_panel.add_child(sb)
	_collision = cs

	# Franja luminosa para leer de un vistazo qué llave pide la puerta.
	var stripe_color := Color(0.5, 0.5, 0.5)
	if requires == "bronze_key_found":
		stripe_color = Color(0.85, 0.55, 0.15)
	elif requires == "keycard_found":
		stripe_color = Color(0.2, 0.7, 0.95)
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(door_size.x + 0.08, 0.22, door_size.z * 0.75)
	stripe.mesh = sm
	stripe.position = Vector3(0, door_size.y * 0.22, 0)
	stripe.material_override = Interactable.make_material(stripe_color, 0.4, stripe_color)
	_panel.add_child(stripe)


func is_unlocked() -> bool:
	return requires.is_empty() or bool(GameState.get(requires))


func can_interact(_player: Node) -> bool:
	return not is_open


func get_prompt(_player: Node) -> String:
	if is_unlocked():
		return "%s — abrir" % door_label
	return "%s — cerrada, necesitan %s" % [door_label, requires_label]


func hold_time(_player: Node) -> float:
	return 1.0 if is_unlocked() else 0.0


func server_interact(_player: Node) -> void:
	if is_open:
		return
	if not is_unlocked():
		GameState.net_message.rpc("La %s necesita %s." % [door_label.to_lower(), requires_label])
		return
	net_set_open.rpc(true)


@rpc("authority", "call_local", "reliable")
func net_set_open(value: bool) -> void:
	is_open = value
	if _panel == null:
		return
	_collision.disabled = value
	var target := Vector3(0, door_size.y * 0.5, 0)
	if value:
		target += Vector3(0, 0, door_size.z * 0.92)
	var tween := create_tween()
	tween.tween_property(_panel, "position", target, 0.8).set_trans(Tween.TRANS_CUBIC)
	if value:
		GameState.objectives_changed.emit()
