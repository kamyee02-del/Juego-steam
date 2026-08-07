extends OmniLight3D
## Titileo de una antorcha. Cada una arranca con un desfase distinto para que no
## parpadeen todas a la vez, que delataría que es el mismo efecto repetido.

const BASE := 2.1

var _fase := 0.0


func _ready() -> void:
	_fase = randf() * TAU


func _process(delta: float) -> void:
	_fase += delta * 7.0
	# Dos ondas de distinta frecuencia: el resultado no se percibe cíclico.
	var t := sin(_fase) * 0.12 + sin(_fase * 2.37) * 0.07
	light_energy = BASE * (1.0 + t)
