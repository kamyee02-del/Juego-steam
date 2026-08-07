extends SceneTree
## Comprueba que las animaciones (que vienen en archivos aparte) apuntan a la
## misma estructura de nodos que los personajes. Si las rutas no coinciden, las
## animaciones no se aplicarían al modelo.
##   godot --headless --script scripts/dev/inspect_anims.gd


func _initialize() -> void:
	print("=== estructura del archivo de animaciones ===")
	var packed: PackedScene = load("res://assets/characters/animations/Rig_Medium_MovementBasic.glb")
	var root := packed.instantiate()
	_print_tree(root, 1)

	var ap: AnimationPlayer = null
	for c in root.get_children():
		if c is AnimationPlayer:
			ap = c
	if ap == null:
		print("  ERROR: sin AnimationPlayer")
		quit(1)
		return

	print("\n=== rutas de las pistas de 'Walking_A' (primeras 6) ===")
	var anim: Animation = ap.get_animation("Walking_A")
	for i in mini(6, anim.get_track_count()):
		print("  ", anim.track_get_path(i))
	print("  ... %d pistas en total" % anim.get_track_count())
	root.free()

	print("\n=== estructura de un personaje ===")
	var pj: PackedScene = load("res://assets/characters/Rogue_Hooded.glb")
	var pjroot := pj.instantiate()
	_print_tree(pjroot, 1)
	pjroot.free()
	quit()


func _print_tree(node: Node, depth: int) -> void:
	if depth > 3:
		return
	var pad := "  ".repeat(depth)
	print("%s%s (%s)" % [pad, node.name, node.get_class()])
	for child in node.get_children():
		_print_tree(child, depth + 1)
