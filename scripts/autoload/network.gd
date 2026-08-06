extends Node
## Gestiona la conexión multijugador. Dos transportes tras la misma API:
## - ENet (IP directa), siempre disponible.
## - Steam (GodotSteam + SteamMultiplayerPeer), si el addon está instalado.

signal lobby_entered
signal join_failed(reason: String)
signal left_game
signal peer_scene_ready(id: int)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8
const LEVEL_SCENE := "res://scenes/level_01.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const STEAM_APP_ID := 480  # AppID de pruebas (SpaceWar). Sustituir por el AppID propio.

enum Transport { NONE, ENET, STEAM }

var transport: int = Transport.NONE
var player_name := "Jugador"
var steam_available := false
var steam_username := ""
var steam_lobby_id := 0
## Quién ha terminado ya de cargar el nivel. Se guarda aquí, y no en el propio
## nivel, porque los clientes suelen cargarlo antes que el anfitrión: si el aviso
## fuera dirigido al nodo del nivel, llegaría cuando aún no existe y se perdería.
var _scene_ready_peers := {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_steam_init()
	_handle_cli_args.call_deferred()


## Permite arrancar dos instancias de prueba sin tocar el menú:
##   godot -- --host --autostart=5
##   godot -- --join=127.0.0.1 --name=Amigo
func _handle_cli_args() -> void:
	var args := OS.get_cmdline_user_args()
	var do_host := false
	var join_ip_addr := ""
	var autostart := -1.0
	for arg in args:
		if arg == "--host":
			do_host = true
		elif arg.begins_with("--join="):
			join_ip_addr = arg.split("=", true, 1)[1]
		elif arg.begins_with("--name="):
			player_name = arg.split("=", true, 1)[1]
		elif arg.begins_with("--autostart="):
			autostart = float(arg.split("=", true, 1)[1])

	if do_host:
		host_ip()
	elif not join_ip_addr.is_empty():
		join_ip(join_ip_addr)

	if do_host and autostart > 0.0:
		await get_tree().create_timer(autostart).timeout
		start_game()


func _process(_delta: float) -> void:
	if steam_available:
		Engine.get_singleton("Steam").call("run_callbacks")


func is_connected_to_game() -> bool:
	return transport != Transport.NONE and multiplayer.multiplayer_peer != null


# --- ENet (IP directa) ---

func host_ip(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	transport = Transport.ENET
	GameState.reset()
	GameState.phase = GameState.Phase.LOBBY
	GameState.add_player(1, player_name)
	lobby_entered.emit()
	return OK


func join_ip(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	transport = Transport.ENET
	GameState.reset()
	return OK


# --- Steam (requiere el addon GodotSteam MultiplayerPeer en addons/) ---

func _steam_init() -> void:
	if not ClassDB.class_exists("SteamMultiplayerPeer") or not Engine.has_singleton("Steam"):
		return
	var steam: Object = Engine.get_singleton("Steam")
	var result: Dictionary = steam.call("steamInitEx", STEAM_APP_ID, true)
	if result.get("status", 1) != 0:
		print("Steam no disponible: ", result)
		return
	steam_available = true
	steam_username = steam.call("getPersonaName")
	player_name = steam_username
	steam.connect("lobby_created", _on_steam_lobby_created)
	steam.connect("lobby_joined", _on_steam_lobby_joined)
	steam.connect("join_requested", _on_steam_join_requested)
	print("Steam iniciado como ", steam_username)


func host_steam() -> Error:
	if not steam_available:
		return ERR_UNAVAILABLE
	var steam: Object = Engine.get_singleton("Steam")
	# 1 = LOBBY_TYPE_FRIENDS_ONLY
	steam.call("createLobby", 1, MAX_PLAYERS)
	return OK


func join_steam_lobby(lobby_id: int) -> Error:
	if not steam_available:
		return ERR_UNAVAILABLE
	GameState.reset()
	var steam: Object = Engine.get_singleton("Steam")
	steam.call("joinLobby", lobby_id)
	return OK


func steam_invite_friends() -> void:
	if steam_available and steam_lobby_id != 0:
		Engine.get_singleton("Steam").call("activateGameOverlayInviteDialog", steam_lobby_id)


func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	if result != 1:
		join_failed.emit("No se pudo crear la sala de Steam (código %d)" % result)
		return
	steam_lobby_id = lobby_id
	var steam: Object = Engine.get_singleton("Steam")
	steam.call("setLobbyJoinable", lobby_id, true)
	steam.call("setLobbyData", lobby_id, "name", player_name + " - Fuga")
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.call("create_host", 0)
	if err != OK:
		join_failed.emit("No se pudo crear el anfitrión de Steam")
		return
	multiplayer.multiplayer_peer = peer
	transport = Transport.STEAM
	GameState.reset()
	GameState.phase = GameState.Phase.LOBBY
	GameState.add_player(1, player_name)
	lobby_entered.emit()


func _on_steam_lobby_joined(lobby_id: int, _perms: int, _locked: bool, response: int) -> void:
	if response != 1:
		join_failed.emit("No se pudo entrar a la sala de Steam (código %d)" % response)
		return
	steam_lobby_id = lobby_id
	var steam: Object = Engine.get_singleton("Steam")
	var owner_id: int = steam.call("getLobbyOwner", lobby_id)
	if owner_id == int(steam.call("getSteamID")):
		return  # somos el anfitrión; ya conectado en _on_steam_lobby_created
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.call("create_client", owner_id, 0)
	if err != OK:
		join_failed.emit("No se pudo conectar con el anfitrión de Steam")
		return
	multiplayer.multiplayer_peer = peer
	transport = Transport.STEAM


func _on_steam_join_requested(lobby_id: int, _friend_id: int) -> void:
	# El jugador aceptó una invitación desde el overlay de Steam.
	join_steam_lobby(lobby_id)


# --- Flujo de partida ---

func start_game() -> void:
	if not multiplayer.is_server():
		return
	_net_start_game.rpc(randi())


func return_to_lobby() -> void:
	if not multiplayer.is_server():
		return
	_net_return_to_lobby.rpc()


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	transport = Transport.NONE
	if steam_available and steam_lobby_id != 0:
		Engine.get_singleton("Steam").call("leaveLobby", steam_lobby_id)
	steam_lobby_id = 0
	GameState.reset()
	left_game.emit()
	_volver_al_menu_y_soltar_peer()


@rpc("authority", "call_local", "reliable")
func _net_start_game(match_seed: int) -> void:
	GameState.match_seed = match_seed
	GameState.reset_run()
	GameState.phase = GameState.Phase.PLAYING
	_scene_ready_peers.clear()
	get_tree().change_scene_to_file(LEVEL_SCENE)


## Lo llama el nivel al terminar de construirse, en todos los pares.
func notify_scene_ready() -> void:
	_net_scene_ready.rpc_id(1)


func scene_ready_peers() -> Dictionary:
	return _scene_ready_peers


@rpc("any_peer", "call_local", "reliable")
func _net_scene_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var id := 1 if sender == 0 else sender
	_scene_ready_peers[id] = true
	peer_scene_ready.emit(id)


@rpc("authority", "call_local", "reliable")
func _net_return_to_lobby() -> void:
	# La fase sigue en ENDED para que el menú muestre el resultado de la ronda;
	# es él quien vuelve a dejarla en LOBBY.
	GameState.reset_run()
	get_tree().change_scene_to_file(MENU_SCENE)


# --- Registro de jugadores ---

@rpc("any_peer", "call_remote", "reliable")
func _net_register(new_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if GameState.phase != GameState.Phase.LOBBY or GameState.players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	var final_name := new_name.strip_edges().substr(0, 20)
	if final_name.is_empty():
		final_name = "Jugador %d" % sender
	GameState.add_player(sender, final_name)
	_net_players.rpc(GameState.players)


@rpc("authority", "call_remote", "reliable")
func _net_players(players: Dictionary) -> void:
	GameState.players = players
	GameState.players_changed.emit()


# --- Señales de conexión ---

func _on_peer_connected(_id: int) -> void:
	pass  # el cliente se registra por sí mismo al conectarse


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var lost_name: String = GameState.player_name(id)
	GameState.remove_player(id)
	_net_players.rpc(GameState.players)
	if GameState.phase == GameState.Phase.PLAYING:
		GameState.net_message.rpc("%s se desconectó" % lost_name)
		var level := get_tree().get_first_node_in_group("level")
		if level != null:
			level.on_player_left(id)


func _on_connected_to_server() -> void:
	GameState.phase = GameState.Phase.LOBBY
	_net_register.rpc_id(1, player_name)
	lobby_entered.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	transport = Transport.NONE
	join_failed.emit("No se pudo conectar con el anfitrión.")


func _on_server_disconnected() -> void:
	# Marcamos la desconexión antes de nada: is_connected_to_game() ya da falso
	# aunque el peer siga un momento en pie.
	transport = Transport.NONE
	GameState.reset()
	join_failed.emit("El anfitrión cerró la partida.")
	_volver_al_menu_y_soltar_peer()


## Descarta el peer solo después de que el nivel haya salido del árbol. Al revés,
## Godot intenta limpiar su caché de red apuntando a nodos que aún existen y
## llena la consola de errores de desconexión.
func _volver_al_menu_y_soltar_peer() -> void:
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path != MENU_SCENE:
		get_tree().change_scene_to_file(MENU_SCENE)
	await get_tree().process_frame
	await get_tree().process_frame
	multiplayer.multiplayer_peer = null
