extends Node3D
## Banco de pruebas del personaje: monta varios modelos en fila, les pone una
## animación y saca capturas para revisarlos a ojo. Se lanza con:
##   godot --resolution 1280x720 --script-scene ... (ver dev/probar_modelo.tscn)

const CARPETA := "user://modelo_shots"

@onready var camara: Camera3D = $Camara


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CARPETA)
	var x := -4.5
	for nombre in ModeloPersonaje.REHENES:
		var m := ModeloPersonaje.new()
		m.name = nombre
		add_child(m)
		if not m.montar(nombre):
			continue
		m.position = Vector3(x, 0, 0)
		x += 1.8
	_secuencia.call_deferred()


func _secuencia() -> void:
	await get_tree().create_timer(0.5).timeout
	await _foto("1_quieto")

	for m in _modelos():
		m.reproducir(ModeloPersonaje.ANDAR)
	await get_tree().create_timer(0.4).timeout
	await _foto("2_andando")

	for m in _modelos():
		m.reproducir(ModeloPersonaje.CORRER)
	await get_tree().create_timer(0.3).timeout
	await _foto("3_corriendo")

	for m in _modelos():
		m.reproducir(ModeloPersonaje.QUIETO)
		m.agachar(true)
	for i in 20:
		for m in _modelos():
			m.agachar(true)
		await get_tree().process_frame
	await _foto("4_agachado")

	print("[PRUEBA] capturas en: ", ProjectSettings.globalize_path(CARPETA))
	get_tree().quit()


func _modelos() -> Array:
	var out: Array = []
	for c in get_children():
		if c is ModeloPersonaje:
			out.append(c)
	return out


func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [CARPETA, nombre])
	print("[PRUEBA] %s.png" % nombre)
