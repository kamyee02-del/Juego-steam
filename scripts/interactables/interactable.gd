class_name Interactable
extends Node3D
## Base de todo lo que el jugador puede usar con la tecla E.
## Crea su propia zona de detección (capa 4 "interact") para que el
## nivel pueda construirlas por código sin escenas sueltas.

@export var interact_radius := 2.0

var _zone: Area3D


func _ready() -> void:
	add_to_group("interactables")
	_zone = Area3D.new()
	_zone.name = "Zone"
	_zone.collision_layer = 8
	_zone.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = interact_radius
	cs.shape = sh
	_zone.add_child(cs)
	add_child(_zone)
	_build()


## Sobrescribir para construir la geometría de la pieza.
func _build() -> void:
	pass


func can_interact(_player: Node) -> bool:
	return true


func get_prompt(_player: Node) -> String:
	return "Usar"


## > 0 para exigir mantener pulsada la tecla ese tiempo en segundos.
func hold_time(_player: Node) -> float:
	return 0.0


## true si el servidor debe seguir el pulsado en tiempo real (palancas a la vez).
func is_continuous() -> bool:
	return false


## Solo se ejecuta en el servidor.
func server_interact(_player: Node) -> void:
	pass


## Solo se ejecuta en el servidor, al empezar/soltar un pulsado continuo.
func server_hold(_player: Node, _holding: bool) -> void:
	pass


# --- Utilidades de construcción ---

static func make_material(color: Color, rough := 0.9, emission := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 1.2
	return m


func add_box(box_size: Vector3, offset: Vector3, color: Color, solid := true, emission := Color.BLACK) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	mi.mesh = bm
	mi.position = offset
	mi.material_override = make_material(color, 0.9, emission)
	add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box_size
		cs.shape = shape
		sb.add_child(cs)
		mi.add_child(sb)
	return mi
