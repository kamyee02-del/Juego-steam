class_name ItemPickup
extends Interactable
## Objeto recogible. La llave y el sello son objetivos del equipo (una vez
## recogidos valen para todos); las botellas se llevan encima y se lanzan.

## El identificador "keycard" se conserva por dentro para no romper nada, pero
## el objeto es el sello del carcelero: un medallón.
@export var item_id := "bronze_key"    # bronze_key | keycard | bottle
@export var item_label := "Llave de bronce"
@export var flag := ""                 # bandera de GameState que activa (si aplica)
@export var item_color := Color(0.85, 0.6, 0.2)

var taken := false
var _visual: Node3D


func _build() -> void:
	interact_radius = 1.8
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.position = Vector3(0, 0.9, 0)
	add_child(_visual)

	var mi := MeshInstance3D.new()
	match item_id:
		"keycard":
			# Medallón: disco grueso colgado de su cadena.
			var sello := CylinderMesh.new()
			sello.top_radius = 0.15
			sello.bottom_radius = 0.15
			sello.height = 0.04
			mi.mesh = sello
			mi.rotation_degrees = Vector3(90, 0, 0)
		"bottle":
			var bottle := CylinderMesh.new()
			bottle.top_radius = 0.05
			bottle.bottom_radius = 0.1
			bottle.height = 0.34
			mi.mesh = bottle
		_:
			var key := BoxMesh.new()
			key.size = Vector3(0.1, 0.1, 0.34)
			mi.mesh = key
	mi.material_override = Interactable.make_material(item_color, 0.3, item_color * 0.7)
	_visual.add_child(mi)

	# Halo tenue para que se vea en la penumbra.
	var glow := OmniLight3D.new()
	glow.light_color = item_color
	glow.light_energy = 0.9
	glow.omni_range = 3.5
	_visual.add_child(glow)


func _process(delta: float) -> void:
	if _visual != null and not taken:
		_visual.rotate_y(delta * 1.4)
		_visual.position.y = 0.9 + sin(Time.get_ticks_msec() / 500.0) * 0.08


func can_interact(_player: Node) -> bool:
	return not taken


func get_prompt(_player: Node) -> String:
	return "Recoger %s" % item_label


func server_interact(player: Node) -> void:
	if taken:
		return
	if item_id == "bottle":
		if player.sync_bottles >= 3:
			GameState.net_message.rpc("No puedes llevar más botellas.")
			return
		player.net_set_bottles.rpc(player.sync_bottles + 1)
	elif not flag.is_empty():
		GameState.net_set_objective.rpc(flag, true)
		GameState.net_message.rpc("%s consiguió: %s" % [GameState.player_name(player.peer_id()), item_label])
	net_set_taken.rpc(true)


@rpc("authority", "call_local", "reliable")
func net_set_taken(value: bool) -> void:
	taken = value
	visible = not value
	if _zone != null:
		_zone.monitorable = not value
