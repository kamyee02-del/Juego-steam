class_name CellGate
extends Interactable
## Reja de una celda. En la celda inicial hay que forzar la cerradura;
## en la celda-prisión sirve para rescatar a los compañeros capturados.

@export var mode := "escape"          # escape | rescue
@export var gate_width := 2.0
@export var gate_height := 3.0

var is_open := false
var _panel: Node3D
var _collision: CollisionShape3D


func _build() -> void:
	interact_radius = 2.2
	_panel = Node3D.new()
	_panel.name = "Panel"
	add_child(_panel)

	var bar_mat := Interactable.make_material(Color(0.45, 0.47, 0.52), 0.35)
	var bars := 7
	for i in bars:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, gate_height, 0.09)
		bar.mesh = bm
		var t := float(i) / float(bars - 1) - 0.5
		bar.position = Vector3(0, gate_height * 0.5, t * gate_width)
		bar.material_override = bar_mat
		_panel.add_child(bar)
	for y in [0.15, gate_height - 0.15]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.11, 0.12, gate_width)
		rail.mesh = rm
		rail.position = Vector3(0, y, 0)
		rail.material_override = bar_mat
		_panel.add_child(rail)

	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, gate_height, gate_width)
	cs.shape = shape
	cs.position = Vector3(0, gate_height * 0.5, 0)
	sb.add_child(cs)
	_panel.add_child(sb)
	_collision = cs


func _captured_waiting() -> bool:
	return not GameState.captured_player_ids().is_empty()


func can_interact(player: Node) -> bool:
	if mode == "escape":
		return not is_open
	# Rescate: solo desde fuera y solo si hay alguien encerrado.
	return player.is_free() and _captured_waiting()


func get_prompt(_player: Node) -> String:
	if mode == "escape":
		return "Forzar la cerradura"
	return "Liberar a tus compañeros"


func hold_time(_player: Node) -> float:
	return 3.0 if mode == "escape" else 4.0


func server_interact(player: Node) -> void:
	var level := get_tree().get_first_node_in_group("level")
	if mode == "escape":
		if is_open:
			return
		net_set_open.rpc(true)
		GameState.net_message.rpc("%s forzó la reja. ¡Salgan con cuidado!" % GameState.player_name(player.peer_id()))
	else:
		if level != null:
			level.free_captured_players(player.peer_id())


@rpc("authority", "call_local", "reliable")
func net_set_open(value: bool) -> void:
	is_open = value
	if _panel == null:
		return
	_collision.disabled = value
	var tween := create_tween()
	tween.tween_property(_panel, "rotation:y", deg_to_rad(-100.0) if value else 0.0, 0.9) \
		.set_trans(Tween.TRANS_BACK)
