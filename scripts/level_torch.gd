extends OmniLight3D
## Titileo de una antorcha. Cada una arranca con un desfase distinto para que no
## parpadeen todas a la vez, que delataría que es el mismo efecto repetido.
## Además de la luz, agita un poco las mallas de la llama: si solo cambiara la
## luz, el fuego se vería como un objeto rígido iluminado de forma rara.

const BASE := 2.1

var _fase := 0.0
var _llamas: Array[MeshInstance3D] = []


func _ready() -> void:
	_fase = randf() * TAU
	# Las mallas de la llama son las hermanas con material emisivo.
	for hermano in get_parent().get_children():
		if hermano is MeshInstance3D:
			var mat := (hermano as MeshInstance3D).material_override
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled:
				_llamas.append(hermano)


func _process(delta: float) -> void:
	_fase += delta * 7.0
	# Dos ondas de distinta frecuencia: el resultado no se percibe cíclico.
	var t := sin(_fase) * 0.12 + sin(_fase * 2.37) * 0.07
	light_energy = BASE * (1.0 + t)

	for i in _llamas.size():
		var llama := _llamas[i]
		var d := _fase + i * 1.7
		# Estira la llama y la bambolea muy poco: de cerca se ve viva, de lejos
		# no distrae.
		llama.scale = Vector3(1.0 + t * 0.5, 1.0 + t * 1.4, 1.0 + t * 0.5)
		llama.rotation.z = sin(d * 0.9) * 0.09
		llama.rotation.x = cos(d * 1.3) * 0.06
