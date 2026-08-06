extends Control
## Menú principal + sala de espera. Ambos paneles viven en la misma escena
## porque tras terminar una partida se vuelve aquí conservando la conexión.

@onready var menu_panel: CenterContainer = $MenuPanel
@onready var lobby_panel: CenterContainer = $LobbyPanel
@onready var name_edit: LineEdit = $MenuPanel/VBox/NameEdit
@onready var ip_edit: LineEdit = $MenuPanel/VBox/JoinRow/IPEdit
@onready var lobby_id_edit: LineEdit = $MenuPanel/VBox/SteamJoinRow/LobbyIdEdit
@onready var status_label: Label = $MenuPanel/VBox/StatusLabel
@onready var steam_host_btn: Button = $MenuPanel/VBox/SteamHostBtn
@onready var steam_join_row: HBoxContainer = $MenuPanel/VBox/SteamJoinRow
@onready var players_list: ItemList = $LobbyPanel/VBox/PlayersList
@onready var start_btn: Button = $LobbyPanel/VBox/StartBtn
@onready var invite_btn: Button = $LobbyPanel/VBox/InviteBtn
@onready var lobby_info: Label = $LobbyPanel/VBox/LobbyInfo
@onready var lobby_status: Label = $LobbyPanel/VBox/LobbyStatus


func _ready() -> void:
	$MenuPanel/VBox/HostBtn.pressed.connect(_on_host_ip)
	$MenuPanel/VBox/JoinRow/JoinBtn.pressed.connect(_on_join_ip)
	$MenuPanel/VBox/SteamJoinRow/SteamJoinBtn.pressed.connect(_on_join_steam)
	$MenuPanel/VBox/QuitBtn.pressed.connect(func() -> void: get_tree().quit())
	steam_host_btn.pressed.connect(_on_host_steam)
	start_btn.pressed.connect(func() -> void: Network.start_game())
	invite_btn.pressed.connect(func() -> void: Network.steam_invite_friends())
	$LobbyPanel/VBox/LeaveBtn.pressed.connect(_on_leave)

	Network.lobby_entered.connect(_show_lobby)
	Network.join_failed.connect(_on_join_failed)
	Network.left_game.connect(_show_menu)
	GameState.players_changed.connect(_refresh_players)

	name_edit.text = Network.player_name
	steam_host_btn.disabled = not Network.steam_available
	steam_join_row.visible = Network.steam_available
	if not Network.steam_available:
		steam_host_btn.text = "Crear partida (Steam no disponible)"

	if GameState.phase == GameState.Phase.ENDED:
		lobby_status.text = "¡Escaparon!" if GameState.last_victory else "Los atraparon a todos..."
		GameState.phase = GameState.Phase.LOBBY

	if Network.is_connected_to_game():
		_show_lobby()
	else:
		_show_menu()


func _show_menu() -> void:
	menu_panel.visible = true
	lobby_panel.visible = false


func _show_lobby() -> void:
	menu_panel.visible = false
	lobby_panel.visible = true
	var is_host := multiplayer.is_server()
	start_btn.visible = is_host
	invite_btn.visible = is_host and Network.steam_available
	if is_host:
		if Network.transport == Network.Transport.STEAM:
			lobby_info.text = "Invita a tus amigos desde Steam.\nID de sala: %d" % Network.steam_lobby_id
		else:
			lobby_info.text = "Comparte tu IP con tus amigos.\nDeben unirse por 'Unirse (IP)' al puerto %d." % Network.DEFAULT_PORT
	else:
		lobby_info.text = "Esperando a que el anfitrión inicie la partida..."
	_refresh_players()


func _refresh_players() -> void:
	if not is_inside_tree() or players_list == null:
		return
	players_list.clear()
	for id in GameState.players:
		var suffix := " (anfitrión)" if id == 1 else ""
		var you := "  ← tú" if id == GameState.local_id() else ""
		var idx := players_list.add_item("%s%s%s" % [GameState.player_name(id), suffix, you])
		players_list.set_item_custom_fg_color(idx, GameState.player_color(id))
	start_btn.disabled = GameState.players.size() < 1


func _current_name() -> String:
	var n := name_edit.text.strip_edges()
	return n if not n.is_empty() else "Jugador"


func _on_host_ip() -> void:
	Network.player_name = _current_name()
	var err := Network.host_ip()
	if err != OK:
		status_label.text = "No se pudo abrir el puerto %d (código %d). ¿Ya hay otra partida abierta?" % [Network.DEFAULT_PORT, err]


func _on_join_ip() -> void:
	Network.player_name = _current_name()
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	status_label.text = "Conectando a %s..." % ip
	var err := Network.join_ip(ip)
	if err != OK:
		status_label.text = "Dirección inválida (código %d)." % err


func _on_host_steam() -> void:
	Network.player_name = _current_name()
	status_label.text = "Creando sala de Steam..."
	var err := Network.host_steam()
	if err != OK:
		status_label.text = "Steam no está disponible. Usa la opción de IP directa."


func _on_join_steam() -> void:
	Network.player_name = _current_name()
	var raw := lobby_id_edit.text.strip_edges()
	if raw.is_valid_int():
		status_label.text = "Entrando a la sala..."
		Network.join_steam_lobby(int(raw))
	else:
		status_label.text = "Acepta la invitación de tu amigo desde el overlay de Steam, o pega el ID de la sala."


func _on_join_failed(reason: String) -> void:
	status_label.text = reason
	_show_menu()


func _on_leave() -> void:
	Network.leave()
	_show_menu()
