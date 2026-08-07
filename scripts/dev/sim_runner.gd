extends Node
## Prueba automática de la partida sin necesidad de teclado ni pantalla.
## Se activa añadiendo --sim a los argumentos:
##   godot --headless -- --host --autostart=5 --sim
## Recorre el plan de fuga completo e imprime el resultado de cada paso.
## Con --sim-guards en su lugar se prueba la detección y captura de los guardias.
## Con --sim-camara se comprueba que el ratón gira la cámara (hace falta pantalla:
## ejecútalo con xvfb-run y --rendering-driver opengl3, no en modo headless).
## Con --shot=carpeta guarda capturas de la partida (útil para revisar el aspecto).
## Añade --diag para volcar cada 3 s la posición de jugadores y guardias.

var level: Node3D
var _diag_timer := 0.0
var _failures := 0


func _ready() -> void:
	level = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_take_screenshots(arg.split("=", true, 1)[1])
	if multiplayer.is_server():
		var args := OS.get_cmdline_user_args()
		# Cada prueba se pide por su nombre. Antes, pedir solo --shot lanzaba
		# también la partida guiada, que movía a los personajes y estropeaba
		# las capturas.
		if args.has("--sim-camara"):
			_run_camara.call_deferred()
		elif args.has("--sim-guards"):
			_run_guards.call_deferred()
		elif args.has("--sim"):
			_run.call_deferred()
	else:
		GameState.game_ended.connect(_report_client_view)


## Comprueba desde el cliente que el estado replicado coincide con el del servidor.
func _report_client_view(victory: bool) -> void:
	_check("[cliente] la partida termina en victoria", victory)
	_check("[cliente] ve los dos objetivos conseguidos", GameState.bronze_key_found and GameState.keycard_found)
	_check("[cliente] ve la corriente cortada y el portón abierto", GameState.power_off and GameState.gate_open)
	_check("[cliente] ve las puertas abiertas",
		_node("Interactables/CellBlockDoor").is_open and _node("Interactables/SecurityDoor").is_open)
	_check("[cliente] ve a todos los jugadores fuera", GameState.escaped_count() == GameState.players.size())
	print("[SIM] === cliente: %s ===" % ("TODO CORRECTO" if _failures == 0 else "%d FALLO(S)" % _failures))


func _process(delta: float) -> void:
	if not OS.get_cmdline_user_args().has("--diag"):
		return
	_diag_timer -= delta
	if _diag_timer > 0.0:
		return
	_diag_timer = 3.0
	var guards: Array = []
	for g in level.guards_node.get_children():
		guards.append("%s st=%d aw=%.2f (%.0f,%.0f)" % [g.name, g.sync_state, g.sync_awareness, g.global_position.x, g.global_position.z])
	var players: Array = []
	for p in level.players_node.get_children():
		players.append("%s st=%d (%.1f,%.1f)" % [p.name, p.sync_state, p.global_position.x, p.global_position.z])
	print("[DIAG %d] jugadores=[%s] guardias=[%s]" % [multiplayer.get_unique_id(), ", ".join(players), ", ".join(guards)])


func _check(label: String, condition: bool) -> void:
	if not condition:
		_failures += 1
	print("[SIM] %s %s" % ["OK  " if condition else "FALLO", label])


func _use(node: Node3D, pid: int) -> void:
	level.find_player(pid).net_teleport.rpc(node.global_position + Vector3(0, 0.2, 1.3))
	await get_tree().create_timer(0.35).timeout
	level.request_interact(node.get_path(), pid)
	await get_tree().create_timer(0.35).timeout


func _node(path: String) -> Node3D:
	return level.get_node(path)


func _run() -> void:
	var tree := get_tree()
	if not level._round_started:
		await level.round_started
	await tree.create_timer(1.0).timeout
	var ids: Array = GameState.players.keys()
	print("[SIM] === plan de fuga con %d jugador(es) ===" % ids.size())

	# Los guardias no deben interferir con la comprobación de mecánicas.
	for g in level.guards_node.get_children():
		g.set_physics_process(false)

	await _use(_node("Interactables/NorthCellGate"), ids[0])
	_check("forzar la reja de la celda", _node("Interactables/NorthCellGate").is_open)

	await _use(_node("Items/BronzeKey"), ids[0])
	_check("recoger la llave de bronce", GameState.bronze_key_found)

	await _use(_node("Items/Keycard"), ids[0])
	_check("recoger la tarjeta de seguridad", GameState.keycard_found)

	await _use(_node("Interactables/CellBlockDoor"), ids[0])
	_check("abrir la puerta del bloque con la llave", _node("Interactables/CellBlockDoor").is_open)

	await _use(_node("Interactables/SecurityDoor"), ids[0])
	_check("abrir la puerta de seguridad con la tarjeta", _node("Interactables/SecurityDoor").is_open)

	var hide := _node("Interactables/Hide0")
	await _use(hide, ids[0])
	_check("esconderse en el armario", hide.occupant == ids[0] and level.find_player(ids[0]).hidden_in == hide)
	level.request_interact(hide.get_path(), ids[0])
	await tree.create_timer(0.35).timeout
	_check("salir del armario", hide.occupant == 0 and level.find_player(ids[0]).hidden_in == null)

	await _use(_node("Items/Bottle0"), ids[0])
	_check("recoger una botella", level.find_player(ids[0]).sync_bottles == 1)
	level.request_throw(ids[0], level.find_player(ids[0]).global_position + Vector3(0, 1.4, 0), Vector3(1, 0, 0))
	await tree.create_timer(0.2).timeout
	_check("lanzar la botella", level.find_player(ids[0]).sync_bottles == 0 and level.bottles_node.get_child_count() == 1)

	# Palancas del generador: hacen falta dos jugadores a la vez.
	var lever_a: CoopLever = _node("Interactables/LeverA")
	var lever_b: CoopLever = _node("Interactables/LeverB")
	level.find_player(ids[0]).net_teleport.rpc(lever_a.global_position + Vector3(0, 0.2, 1.3))
	await tree.create_timer(0.4).timeout
	lever_a.server_hold(level.find_player(ids[0]), true)
	await tree.create_timer(CoopLever.HOLD_REQUIRED + 0.6).timeout
	_check("una sola palanca NO corta la corriente", not GameState.power_off)

	if ids.size() > 1:
		level.find_player(ids[1]).net_teleport.rpc(lever_b.global_position + Vector3(0, 0.2, 1.3))
		await tree.create_timer(0.4).timeout
		lever_b.server_hold(level.find_player(ids[1]), true)
		await tree.create_timer(CoopLever.HOLD_REQUIRED + 0.8).timeout
		_check("las dos palancas a la vez cortan la corriente", GameState.power_off)
	else:
		print("[SIM] (se omite la prueba cooperativa: hace falta un segundo jugador)")
		GameState.net_set_objective.rpc("power_off", true)

	# Captura y rescate.
	level.capture_player(ids[0])
	await tree.create_timer(0.4).timeout
	_check("capturar encierra al jugador", GameState.is_captured(ids[0]) and GameState.phase == GameState.Phase.PLAYING)
	var rescuer: int = ids[-1] if ids.size() > 1 else ids[0]
	if ids.size() > 1:
		level.free_captured_players(rescuer)
		await tree.create_timer(0.4).timeout
		_check("el compañero libera al capturado", GameState.captured_player_ids().is_empty())
	else:
		GameState.net_set_player_flag.rpc(ids[0], "captured", false)
		level.find_player(ids[0]).net_set_state.rpc(0)
		await tree.create_timer(0.3).timeout

	await _use(_node("Interactables/ExitGate"), rescuer)
	_check("abrir el portón con la corriente cortada", _node("Interactables/ExitGate").is_open)

	for pid in ids:
		level.find_player(pid).net_teleport.rpc(level.escape_zone.global_position + Vector3(0, -1.4, 0))
	await tree.create_timer(1.5).timeout
	_check("cruzar la salida gana la partida",
		GameState.phase == GameState.Phase.ENDED and GameState.last_victory and GameState.escaped_count() == ids.size())

	print("[SIM] === %s ===" % ("TODO CORRECTO" if _failures == 0 else "%d PRUEBA(S) FALLIDA(S)" % _failures))
	await tree.create_timer(0.5).timeout
	tree.quit(1 if _failures > 0 else 0)


## Espera hasta que se cumpla la condición o se agote el tiempo. Devuelve si se cumplió.
func _await_until(condition: Callable, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if condition.call():
			return true
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	return condition.call()


func _run_guards() -> void:
	var tree := get_tree()
	if not level._round_started:
		await level.round_started
	await tree.create_timer(1.0).timeout
	var ids: Array = GameState.players.keys()
	print("[SIM] === detección y captura ===")
	var guard: Node3D = level.guards_node.get_node("Guard0")   # patrulla el pasillo de las celdas
	var victim: Node3D = level.find_player(ids[0])

	# Un rehén de pie en mitad del pasillo debe acabar detectado y encerrado.
	victim.net_teleport.rpc(Vector3(14, 0, 20))
	await tree.create_timer(0.5).timeout
	var spotted: bool = await _await_until(func() -> bool: return guard.sync_state == guard.State.CHASE, 20.0)
	_check("el guardia detecta a un rehén a la vista", spotted)
	var caught: bool = await _await_until(func() -> bool: return GameState.is_captured(ids[0]), 15.0)
	_check("el guardia lo persigue y lo captura", caught)
	_check("el capturado acaba en la celda-prisión", victim.global_position.x < 11.0 and victim.global_position.z > 23.0)
	_check("la alerta global se activa al ser vistos", GameState.alert or guard.sync_state != guard.State.CHASE)

	# Escondido en un armario, el mismo guardia no debería encontrarlo.
	if ids.size() > 1:
		var hider: Node3D = level.find_player(ids[1])
		var spot: Node3D = level.get_node("Interactables/Hide0")
		hider.net_teleport.rpc(spot.global_position + Vector3(0, 0.2, 1.3))
		await tree.create_timer(0.4).timeout
		level.request_interact(spot.get_path(), ids[1])
		await tree.create_timer(0.5).timeout
		_check("el segundo rehén se esconde", hider.hidden_in == spot)
		var found: bool = await _await_until(
			func() -> bool: return GameState.is_captured(ids[1]), 18.0)
		_check("escondido no lo encuentran", not found)

	print("[SIM] === %s ===" % ("TODO CORRECTO" if _failures == 0 else "%d PRUEBA(S) FALLIDA(S)" % _failures))
	await tree.create_timer(0.5).timeout
	tree.quit(1 if _failures > 0 else 0)


## Guarda capturas desde varios puntos del mapa para revisar el aspecto del nivel.
func _take_screenshots(dir_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir_path)
	var tree := get_tree()
	await tree.create_timer(3.0).timeout
	var cam := Camera3D.new()
	cam.fov = 70.0
	level.add_child(cam)
	cam.current = true
	# Primeros planos: la cámara se coloca respecto al personaje de verdad, no en
	# un punto fijo, porque los jugadores y guardias se mueven por el mapa.
	for pareja in [["personaje_cerca", level.players_node], ["guardia_cerca", level.guards_node]]:
		var quienes: Array = pareja[1].get_children()
		if quienes.is_empty():
			continue
		var sujeto: Node3D = quienes[0]
		cam.global_position = sujeto.global_position + Vector3(0, 1.3, 3.2)
		cam.look_at(sujeto.global_position + Vector3(0, 0.9, 0), Vector3.UP)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir_path, pareja[0]])
		print("[SHOT] %s/%s.png" % [dir_path, pareja[0]])

	var shots := [
		["celda", Vector3(6, 6, 16), Vector3(6, 1, 4)],
		["pasillo", Vector3(14, 4, 30), Vector3(14, 1, 8)],
		["sala_guardias", Vector3(23, 7, 20), Vector3(23, 0, 6)],
		["generador", Vector3(36, 7, 30), Vector3(36, 0, 42)],
		["patio", Vector3(46, 9, 36), Vector3(62, 0, 23)],
		["general", Vector3(30, 46, 66), Vector3(30, 0, 23)],
	]
	for shot in shots:
		cam.global_position = shot[1]
		cam.look_at(shot[2], Vector3.UP)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [dir_path, shot[0]])
		print("[SHOT] %s/%s.png" % [dir_path, shot[0]])
	cam.queue_free()
	await tree.create_timer(0.3).timeout
	tree.quit()


## Inyecta un movimiento de ratón como si lo hiciera la persona que juega.
func _mover_raton(dx: float, dy: float) -> void:
	var evento := InputEventMouseMotion.new()
	evento.relative = Vector2(dx, dy)
	evento.screen_relative = evento.relative
	# En el centro exacto de la pantalla, que es donde está la mira: si algún
	# elemento del HUD se traga el evento, esta prueba lo destapa.
	evento.position = level.get_viewport().get_visible_rect().size * 0.5
	evento.global_position = evento.position
	Input.parse_input_event(evento)
	await get_tree().process_frame
	await get_tree().process_frame


func _run_camara() -> void:
	var tree := get_tree()
	if not level._round_started:
		await level.round_started
	await tree.create_timer(1.0).timeout
	print("[SIM] === la cámara se gira con el ratón ===")

	var yo: Node3D = level.find_player(GameState.players.keys()[0])
	_check("el ratón queda capturado al empezar", Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)

	var giro0: float = yo.cam_pivot.rotation.y
	var alto0: float = yo.spring_arm.rotation.x

	var carpeta := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camara-shot="):
			carpeta = arg.split("=", true, 1)[1]
	if not carpeta.is_empty():
		DirAccess.make_dir_recursive_absolute(carpeta)
		await _foto_camara(carpeta, "antes")

	await _mover_raton(120.0, 0.0)
	if not carpeta.is_empty():
		await _mover_raton(400.0, -60.0)
		await _foto_camara(carpeta, "despues")
	var giro1: float = yo.cam_pivot.rotation.y
	_check("mover el ratón a los lados gira la cámara (%.3f -> %.3f)" % [giro0, giro1],
		not is_equal_approx(giro0, giro1))

	await _mover_raton(0.0, 90.0)
	var alto1: float = yo.spring_arm.rotation.x
	_check("mover el ratón arriba y abajo cambia el ángulo (%.3f -> %.3f)" % [alto0, alto1],
		not is_equal_approx(alto0, alto1))

	# Un tirón enorme no debe dejar la cámara del revés.
	await _mover_raton(0.0, -100000.0)
	_check("el ángulo se queda dentro del tope superior (%.3f)" % yo.spring_arm.rotation.x,
		yo.spring_arm.rotation.x <= yo.PITCH_MAX + 0.001)
	await _mover_raton(0.0, 200000.0)
	_check("el ángulo se queda dentro del tope inferior (%.3f)" % yo.spring_arm.rotation.x,
		yo.spring_arm.rotation.x >= yo.PITCH_MIN - 0.001)

	print("[SIM] === %s ===" % ("TODO CORRECTO" if _failures == 0 else "%d PRUEBA(S) FALLIDA(S)" % _failures))
	await tree.create_timer(0.3).timeout
	tree.quit(1 if _failures > 0 else 0)


func _foto_camara(carpeta: String, nombre: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	level.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [carpeta, nombre])
	print("[SIM] captura %s/%s.png" % [carpeta, nombre])
