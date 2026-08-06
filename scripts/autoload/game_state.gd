extends Node
## Estado global de la partida. El servidor (anfitrión) es la autoridad:
## todos los cambios llegan a los demás por RPC fiables de este nodo.

signal players_changed
signal alert_changed(alerted: bool)
signal objectives_changed
signal game_ended(victory: bool)
signal message(text: String)

enum Phase { MENU, LOBBY, PLAYING, ENDED }

const PLAYER_COLORS: Array[Color] = [
	Color(0.90, 0.49, 0.13), # naranja
	Color(0.20, 0.60, 0.86), # azul
	Color(0.18, 0.80, 0.44), # verde
	Color(0.95, 0.77, 0.06), # amarillo
	Color(0.61, 0.35, 0.71), # morado
	Color(0.91, 0.30, 0.24), # rojo
	Color(0.10, 0.74, 0.61), # turquesa
	Color(0.93, 0.63, 0.83), # rosa
]

var phase: int = Phase.MENU
## peer_id -> {"name": String, "color": int, "captured": bool, "escaped": bool}
var players: Dictionary = {}
var match_seed: int = 0
var alert := false

# Progreso de los objetivos de escape (compartidos por todo el equipo).
var bronze_key_found := false
var keycard_found := false
var power_off := false
var gate_open := false
var last_victory := false


func reset() -> void:
	phase = Phase.MENU
	players.clear()
	reset_run()
	players_changed.emit()


func reset_run() -> void:
	alert = false
	bronze_key_found = false
	keycard_found = false
	power_off = false
	gate_open = false
	for id in players:
		players[id]["captured"] = false
		players[id]["escaped"] = false
	objectives_changed.emit()


func add_player(id: int, player_name: String) -> void:
	var used_colors: Array = []
	for pid in players:
		used_colors.append(players[pid]["color"])
	var color_idx := 0
	for i in PLAYER_COLORS.size():
		if not used_colors.has(i):
			color_idx = i
			break
	players[id] = {"name": player_name, "color": color_idx, "captured": false, "escaped": false}
	players_changed.emit()


func remove_player(id: int) -> void:
	players.erase(id)
	players_changed.emit()


## Falso entre que el anfitrión cierra y el juego vuelve al menú. Consultar antes
## de usar multiplayer.is_server() o is_multiplayer_authority() en cada fotograma.
func online() -> bool:
	return multiplayer.multiplayer_peer != null


func local_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


func player_color(id: int) -> Color:
	if players.has(id):
		return PLAYER_COLORS[players[id]["color"]]
	return Color.WHITE


func player_name(id: int) -> String:
	if players.has(id):
		return players[id]["name"]
	return "???"


func is_captured(id: int) -> bool:
	return players.has(id) and players[id]["captured"]


func is_escaped(id: int) -> bool:
	return players.has(id) and players[id]["escaped"]


func free_player_ids() -> Array:
	var result: Array = []
	for id in players:
		if not players[id]["captured"] and not players[id]["escaped"]:
			result.append(id)
	return result


func captured_player_ids() -> Array:
	var result: Array = []
	for id in players:
		if players[id]["captured"]:
			result.append(id)
	return result


func escaped_count() -> int:
	var n := 0
	for id in players:
		if players[id]["escaped"]:
			n += 1
	return n


# --- RPCs de sincronización (solo las envía el servidor) ---

@rpc("authority", "call_local", "reliable")
func net_set_player_flag(id: int, key: String, value: bool) -> void:
	if players.has(id):
		players[id][key] = value
		players_changed.emit()


@rpc("authority", "call_local", "reliable")
func net_set_objective(key: String, value: bool) -> void:
	set(key, value)
	objectives_changed.emit()


@rpc("authority", "call_local", "reliable")
func net_set_alert(value: bool) -> void:
	if alert != value:
		alert = value
		alert_changed.emit(value)


@rpc("authority", "call_local", "reliable")
func net_message(text: String) -> void:
	message.emit(text)


@rpc("authority", "call_local", "reliable")
func net_game_over(victory: bool) -> void:
	if phase != Phase.PLAYING:
		return
	phase = Phase.ENDED
	last_victory = victory
	game_ended.emit(victory)
