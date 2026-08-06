extends Node
## Captura las pantallas del menú para poder revisarlas sin jugar a mano.
##   godot -- --menu-shot=carpeta
## Recorre: menú inicial, aviso al pulsar UNIRME sin dirección, intento de
## conexión y sala de espera con la dirección del anfitrión.

var menu: Control


func _ready() -> void:
	menu = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--menu-shot="):
			_capturar(arg.split("=", true, 1)[1])
			return


func _foto(carpeta: String, nombre: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := menu.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [carpeta, nombre])
	print("[MENU-SHOT] %s/%s.png" % [carpeta, nombre])


func _capturar(carpeta: String) -> void:
	DirAccess.make_dir_recursive_absolute(carpeta)
	var tree := get_tree()
	await tree.create_timer(0.5).timeout

	menu.name_edit.text = "Evan el salvaje"
	await _foto(carpeta, "1_menu")

	# El caso que le falló al amigo: pulsar UNIRME con la casilla vacía.
	menu.ip_edit.text = ""
	menu._on_join_ip()
	await tree.create_timer(0.3).timeout
	await _foto(carpeta, "2_sin_direccion")

	# Dirección muerta: debe quedarse "conectando" y rendirse por el tiempo límite.
	menu.ip_edit.text = "10.255.255.1"
	menu._on_join_ip()
	await tree.create_timer(0.6).timeout
	await _foto(carpeta, "3_conectando")

	print("[MENU-SHOT] esperando al tiempo límite de conexión...")
	await tree.create_timer(11.0).timeout
	await _foto(carpeta, "4_tiempo_agotado")
	print("[MENU-SHOT] texto tras agotarse: ", menu.status_label.text.replace("\n", " / "))

	# Y la sala de espera, que ahora enseña la dirección a dictar.
	menu._on_host_ip()
	await tree.create_timer(0.6).timeout
	await _foto(carpeta, "5_sala_de_espera")
	print("[MENU-SHOT] direcciones detectadas: ", Network.local_addresses())

	await tree.create_timer(0.3).timeout
	tree.quit()
