class_name ExitGate
extends Interactable
## Rastrillo de salida. Está trabado por las cadenas del torno y solo se puede
## levantar tras soltarlas (las dos palancas de la sala del torno). Al cruzarlo,
## el jugador escapa.

@export var gate_width := 6.0
@export var gate_height := 4.0

var is_open := false
var _panel: Node3D
var _collision: CollisionShape3D
var _sparks: OmniLight3D


func _build() -> void:
	interact_radius = 3.0
	_panel = Node3D.new()
	_panel.name = "Panel"
	add_child(_panel)

	var mat := Interactable.make_material(Color(0.3, 0.32, 0.36), 0.4)
	for i in 9:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, gate_height, 0.14)
		bar.mesh = bm
		bar.position = Vector3(0, gate_height * 0.5, (float(i) / 8.0 - 0.5) * gate_width)
		bar.material_override = mat
		_panel.add_child(bar)
	for y in [0.3, gate_height * 0.55, gate_height - 0.2]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.16, 0.16, gate_width)
		rail.mesh = rm
		rail.position = Vector3(0, y, 0)
		rail.material_override = mat
		_panel.add_child(rail)

	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, gate_height, gate_width)
	cs.shape = shape
	cs.position = Vector3(0, gate_height * 0.5, 0)
	sb.add_child(cs)
	_panel.add_child(sb)
	_collision = cs

	_sparks = OmniLight3D.new()
	_sparks.light_color = Color(0.3, 0.7, 1.0)
	_sparks.light_energy = 1.6
	_sparks.omni_range = 7.0
	_sparks.position = Vector3(0, gate_height * 0.6, 0)
	add_child(_sparks)


func _process(delta: float) -> void:
	if _sparks == null:
		return
	# Brasero junto al rastrillo: rojo mientras sigue trabado, verde al soltarse.
	if GameState.power_off or is_open:
		_sparks.light_color = Color(0.45, 1.0, 0.5)
		_sparks.light_energy = 1.2
	else:
		_sparks.light_color = Color(1.0, 0.45, 0.2)
		_sparks.light_energy = 1.6 + sin(Time.get_ticks_msec() / 220.0) * 0.5
	_sparks.rotate_y(delta * 0.2)


func can_interact(_player: Node) -> bool:
	return not is_open


func get_prompt(_player: Node) -> String:
	if GameState.power_off:
		return "Rastrillo — levantarlo y salir de aquí"
	return "Rastrillo trabado — suelten las cadenas en la sala del torno"


func hold_time(_player: Node) -> float:
	return 2.5 if GameState.power_off else 0.0


func server_interact(_player: Node) -> void:
	if is_open:
		return
	if not GameState.power_off:
		GameState.net_message.rpc("El rastrillo sigue trabado. Hay que soltar las cadenas del torno.")
		return
	net_set_open.rpc(true)
	GameState.net_set_objective.rpc("gate_open", true)
	GameState.net_message.rpc("¡El rastrillo está arriba! ¡Corran a la salida!")


@rpc("authority", "call_local", "reliable")
func net_set_open(value: bool) -> void:
	is_open = value
	if _panel == null:
		return
	_collision.disabled = value
	var tween := create_tween()
	tween.tween_property(_panel, "position:y", gate_height * 0.98 if value else 0.0, 1.6) \
		.set_trans(Tween.TRANS_SINE)
