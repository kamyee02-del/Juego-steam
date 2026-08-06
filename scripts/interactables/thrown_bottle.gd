extends RigidBody3D
## Botella lanzada. Al chocar hace un ruido fuerte que atrae a los guardias
## hacia el punto de impacto: la herramienta de distracción del equipo.

const NOISE_RADIUS := 22.0
const LIFETIME := 12.0

var _broken := false
var _life := LIFETIME


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	if not multiplayer.is_server():
		freeze = true   # los clientes solo muestran la posición replicada


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(_body: Node) -> void:
	if _broken or not multiplayer.is_server():
		return
	_broken = true
	var level := get_tree().get_first_node_in_group("level")
	if level != null:
		level.server_noise(global_position, NOISE_RADIUS)
		level.net_bottle_break.rpc(global_position)
	_life = minf(_life, 3.0)
