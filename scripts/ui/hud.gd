extends CanvasLayer
## Interfaz de la partida: objetivos, estado del equipo, avisos de sigilo,
## indicaciones de interacción y pantalla de resultados.

## Los identificadores internos (keycard_found, power_off...) se mantienen para
## no romper nada; lo que cambia es el texto que lee quien juega.
const OBJECTIVES := [
	["Salir de la celda", "cell"],
	["Encontrar la llave de bronce", "bronze_key_found"],
	["Encontrar el sello del carcelero", "keycard_found"],
	["Soltar las cadenas del rastrillo (2 personas)", "power_off"],
	["Levantar el rastrillo y escapar", "gate_open"],
]

var level: Node = null
var player: Node = null

@onready var alert_label: Label = $Alert
@onready var team_box: VBoxContainer = $Team
@onready var messages_box: VBoxContainer = $Messages
@onready var prompt_label: Label = $PromptBox/Prompt
@onready var hold_bar: ProgressBar = $PromptBox/HoldBar
@onready var inventory_label: Label = $Inventory
@onready var status_overlay: Label = $StatusOverlay
@onready var end_panel: ColorRect = $EndPanel
@onready var end_title: Label = $EndPanel/Center/VBox/EndTitle
@onready var end_detail: Label = $EndPanel/Center/VBox/EndDetail
@onready var return_btn: Button = $EndPanel/Center/VBox/ReturnBtn
@onready var crosshair: ColorRect = $Crosshair


func _ready() -> void:
	level = get_parent()
	level.local_player_spawned.connect(_on_local_player)
	GameState.objectives_changed.connect(_refresh_objectives)
	GameState.players_changed.connect(_refresh_team)
	GameState.alert_changed.connect(func(_v: bool) -> void: _refresh_objectives())
	GameState.message.connect(_push_message)
	GameState.game_ended.connect(_on_game_ended)
	return_btn.pressed.connect(func() -> void: Network.return_to_lobby())
	$EndPanel/Center/VBox/LeaveBtn.pressed.connect(func() -> void: Network.leave())
	hold_bar.visible = false
	_refresh_objectives()
	_refresh_team()


func _on_local_player(p: Node) -> void:
	player = p


func _process(_delta: float) -> void:
	_update_alert()
	_update_prompt()
	_update_status()


# --- Objetivos ---

func _refresh_objectives() -> void:
	var cell_gate := level.get_node_or_null("Interactables/NorthCellGate") if level != null else null
	for i in OBJECTIVES.size():
		var label: Label = $Objectives.get_node_or_null("Obj%d" % (i + 1))
		if label == null:
			continue
		var key: String = OBJECTIVES[i][1]
		var done := false
		if key == "cell":
			done = cell_gate != null and cell_gate.is_open
		else:
			done = bool(GameState.get(key))
		label.text = ("  [x] %s" if done else "  [ ] %s") % OBJECTIVES[i][0]
		label.modulate = Color(0.45, 0.9, 0.55) if done else Color(0.88, 0.9, 0.95)


func _refresh_team() -> void:
	for child in team_box.get_children():
		if child.name != "TeamTitle":
			child.queue_free()
	for pid in GameState.players:
		var row := Label.new()
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var state := "libre"
		var tint: Color = GameState.player_color(pid)
		if GameState.is_escaped(pid):
			state = "FUERA"
			tint = Color(0.45, 0.95, 0.55)
		elif GameState.is_captured(pid):
			state = "capturado"
			tint = Color(0.95, 0.35, 0.3)
		row.text = "%s — %s" % [GameState.player_name(pid), state]
		row.modulate = tint
		team_box.add_child(row)


# --- Sigilo ---

func _update_alert() -> void:
	var worst := 0.0
	var chasing := false
	var suspicious := false
	if level != null:
		for g in level.get_node("Guards").get_children():
			if g.sync_state == 2:      # CHASE
				chasing = true
			elif g.sync_state == 1:    # SUSPICIOUS
				suspicious = true
			worst = maxf(worst, g.sync_awareness)

	if chasing:
		alert_label.text = "¡TE PERSIGUEN!"
		alert_label.modulate = Color(1.0, 0.28, 0.24)
	elif suspicious:
		alert_label.text = "SOSPECHAN ALGO"
		alert_label.modulate = Color(1.0, 0.65, 0.2)
	elif worst > 0.08:
		alert_label.text = "TE ESTÁN VIENDO..."
		alert_label.modulate = Color(1.0, 0.9, 0.4, clampf(0.35 + worst, 0.0, 1.0))
	else:
		alert_label.text = "OCULTOS"
		alert_label.modulate = Color(0.55, 0.75, 0.6, 0.55)


func _update_prompt() -> void:
	if player == null or not is_instance_valid(player):
		prompt_label.text = ""
		hold_bar.visible = false
		inventory_label.text = ""
		return

	inventory_label.text = "Botellas: %d  (Q para lanzar)" % player.sync_bottles

	var target = player.interact_target
	if target == null or not is_instance_valid(target) or not player.is_free():
		prompt_label.text = ""
		hold_bar.visible = false
		return
	prompt_label.text = "[E] %s" % target.get_prompt(player)
	var needs_hold: bool = float(target.hold_time(player)) > 0.0
	hold_bar.visible = needs_hold and player.hold_progress > 0.001
	hold_bar.value = player.hold_progress


func _update_status() -> void:
	if player == null or not is_instance_valid(player):
		status_overlay.text = ""
		return
	crosshair.visible = player.is_free()
	match player.sync_state:
		1:  # CAPTURED
			status_overlay.text = "Estás encerrado en la celda sur.\nEspera a que un compañero te libere."
			status_overlay.modulate = Color(1.0, 0.5, 0.45)
		2:  # ESCAPED
			status_overlay.text = "¡Estás fuera!\nEsperando a los demás..."
			status_overlay.modulate = Color(0.5, 0.95, 0.6)
		_:
			if player.hidden_in != null:
				status_overlay.text = "Escondido. Pulsa E otra vez para salir."
				status_overlay.modulate = Color(0.7, 0.85, 1.0)
			else:
				status_overlay.text = ""


# --- Avisos ---

func _push_message(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(430, 0)
	messages_box.add_child(label)
	while messages_box.get_child_count() > 5:
		var old := messages_box.get_child(0)
		messages_box.remove_child(old)
		old.queue_free()
	# El tween cuelga del propio aviso: si se retira antes, muere con él.
	var tween := label.create_tween()
	tween.tween_interval(7.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.5)
	tween.tween_callback(label.queue_free)


# --- Fin de ronda ---

func _on_game_ended(victory: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	end_panel.visible = true
	var escaped: Array = []
	var caught: Array = []
	for pid in GameState.players:
		if GameState.is_escaped(pid):
			escaped.append(GameState.player_name(pid))
		else:
			caught.append(GameState.player_name(pid))

	if victory and caught.is_empty():
		end_title.text = "¡FUGA PERFECTA!"
		end_title.modulate = Color(0.45, 0.95, 0.55)
		end_detail.text = "Salieron todos sin dejar a nadie atrás."
	elif victory:
		end_title.text = "FUGA PARCIAL"
		end_title.modulate = Color(0.95, 0.8, 0.35)
		end_detail.text = "Escaparon: %s\nSe quedaron dentro: %s" % [", ".join(escaped), ", ".join(caught)]
	else:
		end_title.text = "LOS ATRAPARON"
		end_title.modulate = Color(0.95, 0.35, 0.3)
		end_detail.text = "Nadie logró cruzar el portón. Otra vez será."

	return_btn.visible = multiplayer.is_server()
