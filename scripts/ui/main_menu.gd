extends Control
## Menú principal + sala de espera. Ambos paneles viven en la misma escena
## porque tras terminar una partida se vuelve aquí conservando la conexión.

const JOIN_TIMEOUT := 10.0

var _joining_address := ""
var _join_timer: SceneTreeTimer = null

@onready var menu_panel: CenterContainer = $MenuPanel
@onready var lobby_panel: CenterContainer = $LobbyPanel
@onready var name_edit: LineEdit = $MenuPanel/VBox/NameEdit
@onready var host_btn: Button = $MenuPanel/VBox/HostBox/VBox/HostBtn
@onready var ip_edit: LineEdit = $MenuPanel/VBox/JoinBox/VBox/JoinRow/IPEdit
@onready var join_btn: Button = $MenuPanel/VBox/JoinBox/VBox/JoinRow/JoinBtn
@onready var lobby_id_edit: LineEdit = $MenuPanel/VBox/SteamBox/SteamJoinRow/LobbyIdEdit
@onready var status_label: Label = $MenuPanel/VBox/StatusLabel
@onready var steam_host_btn: Button = $MenuPanel/VBox/SteamBox/SteamHostBtn
@onready var steam_join_row: HBoxContainer = $MenuPanel/VBox/SteamBox/SteamJoinRow
@onready var steam_nota: Label = $MenuPanel/VBox/SteamBox/SteamNota
@onready var players_list: ItemList = $LobbyPanel/VBox/PlayersList
@onready var start_btn: Button = $LobbyPanel/VBox/StartBtn
@onready var invite_btn: Button = $LobbyPanel/VBox/InviteBtn
@onready var lobby_info: Label = $LobbyPanel/VBox/LobbyInfo
@onready var lobby_status: Label = $LobbyPanel/VBox/LobbyStatus
@onready var address_box: PanelContainer = $LobbyPanel/VBox/AddressBox
@onready var address_label: Label = $LobbyPanel/VBox/AddressBox/VBox/Direccion
@onready var address_note: Label = $LobbyPanel/VBox/AddressBox/VBox/Nota


func _ready() -> void:
	host_btn.pressed.connect(_on_host_ip)
	join_btn.pressed.connect(_on_join_ip)
	ip_edit.text_submitted.connect(func(_t: String) -> void: _on_join_ip())
	$MenuPanel/VBox/SteamBox/SteamJoinRow/SteamJoinBtn.pressed.connect(_on_join_steam)
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
		steam_nota.text = "Las invitaciones por Steam no están activas en esta versión. Usa los dos recuadros de arriba."

	if GameState.phase == GameState.Phase.ENDED:
		lobby_status.text = "¡Escaparon!" if GameState.last_victory else "Los atraparon a todos..."
		GameState.phase = GameState.Phase.LOBBY

	if Network.is_connected_to_game():
		_show_lobby()
	else:
		_show_menu()
	_add_dev_shots()


## Herramienta de revisión del menú. Como el arnés del nivel, se carga con
## load() porque scripts/dev no se incluye al exportar el juego.
func _add_dev_shots() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--menu-shot="):
			const RUTA := "res://scripts/dev/menu_shots.gd"
			if ResourceLoader.exists(RUTA):
				var guion: GDScript = load(RUTA)
				add_child(guion.new())
			return


func _show_menu() -> void:
	_cancel_join_timer()
	_set_busy(false)
	menu_panel.visible = true
	lobby_panel.visible = false


func _show_lobby() -> void:
	_cancel_join_timer()
	_set_busy(false)
	menu_panel.visible = false
	lobby_panel.visible = true
	var is_host := multiplayer.is_server()
	start_btn.visible = is_host
	invite_btn.visible = is_host and Network.steam_available
	address_box.visible = is_host and Network.transport == Network.Transport.ENET

	if not is_host:
		lobby_info.text = "Esperando a que el anfitrión inicie la partida..."
	elif Network.transport == Network.Transport.STEAM:
		lobby_info.text = "Invita a tus amigos desde Steam.\nID de sala: %d" % Network.steam_lobby_id
	else:
		lobby_info.text = "Cuando estén todos en la lista, pulsa «Iniciar partida»."
		_show_host_address()
	_refresh_players()


## Enseña la dirección del anfitrión para que la dicte, en vez de obligarle a
## buscarla con ipconfig.
func _show_host_address() -> void:
	var direcciones := Network.local_addresses()
	if direcciones.is_empty():
		address_label.text = "no se pudo detectar"
		address_note.text = "Búscala con «ipconfig» en Windows o en Ajustes → Red en Mac."
		return
	address_label.text = direcciones[0]
	var nota := "Puerto %d. " % Network.DEFAULT_PORT
	if direcciones.size() > 1:
		nota += "Si esa no les funciona, probad con: %s. " % ", ".join(direcciones.slice(1))
	nota += "Solo vale si estáis en la misma red; si cada uno está en su casa, usad antes una red virtual."
	address_note.text = nota


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


## Bloquea los botones mientras se está intentando conectar.
func _set_busy(busy: bool) -> void:
	host_btn.disabled = busy
	join_btn.disabled = busy
	ip_edit.editable = not busy
	steam_host_btn.disabled = busy or not Network.steam_available


func _cancel_join_timer() -> void:
	_join_timer = null
	_joining_address = ""


func _on_host_ip() -> void:
	Network.player_name = _current_name()
	var err := Network.host_ip()
	if err != OK:
		status_label.text = "No se pudo abrir el puerto %d (código %d). ¿Tienes ya otra partida abierta?" % [Network.DEFAULT_PORT, err]


func _on_join_ip() -> void:
	var texto := ip_edit.text.strip_edges()
	if texto.is_empty():
		status_label.text = "Escribe aquí la dirección del anfitrión. Te la tiene que pasar quien creó la partida: le aparece en su pantalla nada más crearla."
		ip_edit.grab_focus()
		return

	# Mucha gente pega la dirección con el puerto incluido.
	var direccion := texto
	var puerto := Network.DEFAULT_PORT
	var partes := texto.rsplit(":", true, 1)
	if partes.size() == 2 and partes[1].is_valid_int() and not partes[0].contains(":"):
		direccion = partes[0].strip_edges()
		puerto = int(partes[1])
	if direccion.is_empty():
		status_label.text = "Esa dirección no parece válida. Debe ser algo como 192.168.1.50"
		return

	Network.player_name = _current_name()
	_joining_address = direccion
	status_label.text = "Conectando a %s..." % direccion
	_set_busy(true)

	var err := Network.join_ip(direccion, puerto)
	if err != OK:
		_set_busy(false)
		_joining_address = ""
		status_label.text = "«%s» no parece una dirección válida. Debe ser algo como 192.168.1.50" % direccion
		return

	# Si el anfitrión no existe, ENet puede tardar mucho en rendirse o no hacerlo.
	var timer := get_tree().create_timer(JOIN_TIMEOUT)
	_join_timer = timer
	await timer.timeout
	if _join_timer != timer or Network.is_in_lobby():
		return
	Network.cancel_join()
	_set_busy(false)
	status_label.text = "No se pudo conectar con %s.\nComprueba que esa persona tenga la partida creada en este momento y que estéis en la misma red (o en la misma red virtual)." % direccion
	_joining_address = ""


func _on_host_steam() -> void:
	Network.player_name = _current_name()
	status_label.text = "Creando sala de Steam..."
	var err := Network.host_steam()
	if err != OK:
		status_label.text = "Steam no está disponible en esta versión. Usa «CREAR PARTIDA»."


func _on_join_steam() -> void:
	Network.player_name = _current_name()
	var raw := lobby_id_edit.text.strip_edges()
	if raw.is_valid_int():
		status_label.text = "Entrando a la sala..."
		Network.join_steam_lobby(int(raw))
	else:
		status_label.text = "Acepta la invitación de tu amigo desde el overlay de Steam, o pega el ID de la sala."


func _on_join_failed(reason: String) -> void:
	_cancel_join_timer()
	_set_busy(false)
	status_label.text = reason
	_show_menu()


func _on_leave() -> void:
	Network.leave()
	_show_menu()
