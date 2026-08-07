class_name HidingSpot
extends Interactable
## Armario, arcón o barril donde esconderse. Mientras estás dentro los guardias
## no te ven, pero tampoco puedes moverte.

@export var spot_label := "Armario"
@export var spot_size := Vector3(1.0, 2.0, 0.9)
@export var spot_color := Color(0.30, 0.21, 0.13)   # madera vieja

var occupant := 0   # peer id, 0 si está libre


func _build() -> void:
	interact_radius = 1.9
	add_box(spot_size, Vector3(0, spot_size.y * 0.5, 0), spot_color)
	var handle := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.08, 0.3, 0.08)
	handle.mesh = hm
	handle.position = Vector3(spot_size.x * 0.35, spot_size.y * 0.55, spot_size.z * 0.55)
	handle.material_override = Interactable.make_material(Color(0.45, 0.38, 0.22), 0.4)   # herraje
	add_child(handle)


func can_interact(player: Node) -> bool:
	if not player.is_free():
		return false
	return occupant == 0 or occupant == player.peer_id()


func get_prompt(player: Node) -> String:
	if occupant == player.peer_id():
		return "Salir del %s" % spot_label.to_lower()
	return "Esconderse en el %s" % spot_label.to_lower()


func server_interact(player: Node) -> void:
	var pid: int = player.peer_id()
	if occupant == pid:
		net_set_occupant.rpc(0)
		player.net_set_hidden.rpc(NodePath())
		# Salir un paso al frente para no quedarse dentro del mueble.
		player.net_teleport.rpc(global_position + Vector3(0, 0.1, 0) + global_transform.basis.z * 1.3)
	elif occupant == 0:
		net_set_occupant.rpc(pid)
		var level := get_tree().get_first_node_in_group("level")
		player.net_teleport.rpc(global_position + Vector3(0, 0.1, 0))
		player.net_set_hidden.rpc(level.get_path_to(self))


@rpc("authority", "call_local", "reliable")
func net_set_occupant(pid: int) -> void:
	occupant = pid
