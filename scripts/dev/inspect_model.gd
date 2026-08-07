extends SceneTree
## Herramienta de revisión de los modelos de personaje. Se ejecuta con:
##   godot --headless --script scripts/dev/inspect_model.gd

const MODELOS := [
	"res://assets/characters/Knight.glb",
	"res://assets/characters/Rogue_Hooded.glb",
	"res://assets/characters/Barbarian.glb",
	"res://assets/characters/Mage.glb",
	"res://assets/characters/Ranger.glb",
	"res://assets/characters/Rogue.glb",
]


func _initialize() -> void:
	for ruta in MODELOS:
		_medir(ruta)
	_huesos()
	quit()


func _medir(ruta: String) -> void:
	var packed: PackedScene = load(ruta)
	var root := packed.instantiate()
	var caja := AABB()
	var primero := true
	for mi in _mallas(root):
		var propia: AABB = mi.get_aabb()
		if primero:
			caja = propia
			primero = false
		else:
			caja = caja.merge(propia)
	print("%-18s alto:%.2f ancho:%.2f fondo:%.2f base_y:%.2f textura:%s" % [
		ruta.get_file(), caja.size.y, caja.size.x, caja.size.z, caja.position.y,
		_tiene_textura(root)])
	root.free()


func _mallas(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_mallas(c))
	return out


func _tiene_textura(root: Node) -> String:
	for mi in _mallas(root):
		var mat: Material = mi.mesh.surface_get_material(0)
		if mat is BaseMaterial3D:
			var tex: Texture2D = (mat as BaseMaterial3D).albedo_texture
			return "SI" if tex != null else "NO"
	return "?"


func _huesos() -> void:
	print("\n=== huesos del esqueleto ===")
	var packed: PackedScene = load("res://assets/characters/Knight.glb")
	var root := packed.instantiate()
	for n in _buscar_esqueleto(root):
		var nombres: Array = []
		for i in n.get_bone_count():
			nombres.append(n.get_bone_name(i))
		print(", ".join(nombres))
	root.free()


func _buscar_esqueleto(node: Node) -> Array:
	var out: Array = []
	if node is Skeleton3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_buscar_esqueleto(c))
	return out
