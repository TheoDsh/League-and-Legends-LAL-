extends Control

const GameData = preload("res://script/game_data.gd")
const MATCH_SIM_SCRIPT := "res://script/match_sim.gd"
const ADVANTAGE_GRAPH_SCRIPT := "res://script/advantage_graph.gd"
const MENU_SCENE := "res://scene/menu.tscn"
const CHAMPIONS_FILE := "res://data/champions.json"
const ITEMS_FILE := "res://data/items.json"
const ROLES: Array[String] = ["top", "jgl", "mid", "bot", "sup"]
const TURN_SECONDS := 60

@onready var player_club_label: Label = $player_club_label
@onready var opponent_club_label: Label = $opponent_club_label
@onready var search_button: Button = $search_match_button
@onready var back_button: Button = $back_button

var player_club_id := ""
var opponent_ai_club_id := ""
var ai_clubs: Array[Dictionary] = []
var champions: Dictionary = {}
var items: Dictionary = {}
var champions_by_role: Dictionary = {}
var selected_role := "top"

var draft_steps: Array[Dictionary] = []
var current_step := -1
var turn_time_left := 0.0
var draft_running := false
var resolving_ai_turn := false

var banned_champions: Array[String] = []
var player_picks: Array[String] = []
var ai_picks: Array[String] = []

var phase_label: Label
var timer_label: Label
var player_summary_label: Label
var ai_summary_label: Label
var draft_panel: Panel
var grid_panel: Panel
var role_tabs: HBoxContainer
var champion_grid: GridContainer
var champion_popup: Panel
var popup_image: TextureRect
var popup_info: Label
var popup_pick_button: Button
var popup_ban_button: Button
var popup_back_button: Button
var popup_champion_id := ""

var match_sim
var match_running := false
var match_speed: float = 1.0
var match_panel: Panel
var advantage_graph
var match_time_label: Label
var match_speed_buttons: Dictionary = {}
var match_status_label: Label
var player_total_gold_label: Label
var ai_total_gold_label: Label
var event_log_label: Label
var match_rows: Dictionary = {"player": {}, "ai": {}}
var lane_diff_labels: Dictionary = {}

func _ready() -> void:
	randomize()
	search_button.pressed.connect(_on_search_match_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_show_player_club()
	_load_ai_clubs()
	_load_champions()
	items = _read_json_file(ITEMS_FILE)
	_build_draft_steps()
	_build_draft_ui()
	_build_match_ui()
	_set_draft_ui_visible(false)
	_set_match_ui_visible(false)

func _process(delta: float) -> void:
	if match_running:
		match_sim.step(delta * match_speed)
		_refresh_match_ui()
		return

	if not draft_running or not _is_player_turn():
		return

	turn_time_left -= delta
	_update_phase_labels()
	if turn_time_left <= 0.0:
		_auto_pick_for_player()

func _show_player_club() -> void:
	var email := str(get_tree().get_meta("current_user_email", ""))
	player_club_id = GameData.get_user_club_id(email)
	var clubs := GameData.load_clubs()
	if clubs.has(player_club_id) and typeof(clubs[player_club_id]) == TYPE_DICTIONARY:
		var club: Dictionary = clubs[player_club_id]
		player_club_label.text = str(club.get("name", "YOUR CLUB"))
	else:
		player_club_label.text = "YOUR CLUB"

	opponent_club_label.text = ""

func _load_ai_clubs() -> void:
	ai_clubs.clear()
	var clubs := GameData.load_clubs()
	for club_id in clubs:
		var club = clubs[club_id]
		if typeof(club) != TYPE_DICTIONARY:
			continue

		if str(club.get("type", "")) == "ai":
			ai_clubs.append({"id": str(club_id), "name": str(club.get("name", club_id))})

func _load_champions() -> void:
	champions = _read_json_file(CHAMPIONS_FILE)
	champions_by_role.clear()
	for role in ROLES:
		champions_by_role[role] = []

	for champion_id in champions:
		var champion = champions[champion_id]
		if typeof(champion) != TYPE_DICTIONARY:
			continue

		var role := str(champion.get("role", ""))
		if champions_by_role.has(role):
			champions_by_role[role].append(str(champion_id))

func _build_draft_steps() -> void:
	draft_steps.clear()
	for i in range(2):
		draft_steps.append({"actor": "player", "action": "ban"})
		draft_steps.append({"actor": "ai", "action": "ban"})

	draft_steps.append({"actor": "player", "action": "pick"})
	draft_steps.append({"actor": "ai", "action": "pick"})

	draft_steps.append({"actor": "player", "action": "ban"})
	draft_steps.append({"actor": "ai", "action": "ban"})

	for i in range(4):
		draft_steps.append({"actor": "player", "action": "pick"})
		draft_steps.append({"actor": "ai", "action": "pick"})

func _build_draft_ui() -> void:
	draft_panel = Panel.new()
	draft_panel.position = Vector2(45, 865)
	draft_panel.size = Vector2(990, 790)
	draft_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.02, 0.025, 0.035, 0.88)))
	add_child(draft_panel)

	phase_label = Label.new()
	phase_label.position = Vector2(90, 885)
	phase_label.size = Vector2(900, 55)
	phase_label.add_theme_font_size_override("font_size", 34)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(phase_label)

	timer_label = Label.new()
	timer_label.position = Vector2(385, 940)
	timer_label.size = Vector2(310, 55)
	timer_label.add_theme_font_size_override("font_size", 36)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(timer_label)

	role_tabs = HBoxContainer.new()
	role_tabs.position = Vector2(70, 1010)
	role_tabs.size = Vector2(940, 70)
	role_tabs.add_theme_constant_override("separation", 10)
	add_child(role_tabs)

	for role in ROLES:
		var role_button := Button.new()
		role_button.text = role.to_upper()
		role_button.custom_minimum_size = Vector2(176, 58)
		role_button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.08, 0.09, 0.12, 0.95)))
		role_button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.14, 0.15, 0.2, 1.0)))
		role_button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.2, 0.22, 0.3, 1.0)))
		role_button.add_theme_color_override("font_color", Color.WHITE)
		role_button.add_theme_font_size_override("font_size", 28)
		role_button.pressed.connect(_on_role_tab_pressed.bind(role))
		role_tabs.add_child(role_button)

	grid_panel = Panel.new()
	grid_panel.position = Vector2(55, 1080)
	grid_panel.size = Vector2(970, 455)
	grid_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.01, 0.015, 0.025, 0.72)))
	add_child(grid_panel)

	var scroll := ScrollContainer.new()
	scroll.name = "champion_scroll"
	scroll.position = Vector2(70, 1090)
	scroll.size = Vector2(940, 430)
	add_child(scroll)

	champion_grid = GridContainer.new()
	champion_grid.columns = 5
	champion_grid.add_theme_constant_override("h_separation", 16)
	champion_grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(champion_grid)

	player_summary_label = Label.new()
	player_summary_label.position = Vector2(70, 1525)
	player_summary_label.size = Vector2(450, 115)
	player_summary_label.add_theme_font_size_override("font_size", 24)
	player_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(player_summary_label)

	ai_summary_label = Label.new()
	ai_summary_label.position = Vector2(560, 1525)
	ai_summary_label.size = Vector2(450, 115)
	ai_summary_label.add_theme_font_size_override("font_size", 24)
	ai_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(ai_summary_label)

	_build_champion_popup()
	_refresh_champion_grid()

func _build_champion_popup() -> void:
	champion_popup = Panel.new()
	champion_popup.position = Vector2(55, 265)
	champion_popup.size = Vector2(970, 1040)
	champion_popup.add_theme_stylebox_override("panel", _make_panel_style(Color(0.015, 0.018, 0.025, 0.96)))
	champion_popup.visible = false
	add_child(champion_popup)

	popup_image = TextureRect.new()
	popup_image.position = Vector2(325, 45)
	popup_image.size = Vector2(320, 320)
	popup_image.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	popup_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	champion_popup.add_child(popup_image)

	popup_info = Label.new()
	popup_info.position = Vector2(65, 390)
	popup_info.size = Vector2(840, 380)
	popup_info.add_theme_font_size_override("font_size", 34)
	popup_info.add_theme_color_override("font_color", Color.WHITE)
	popup_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	champion_popup.add_child(popup_info)

	popup_pick_button = Button.new()
	popup_pick_button.position = Vector2(95, 840)
	popup_pick_button.size = Vector2(235, 95)
	popup_pick_button.text = "PICK"
	popup_pick_button.add_theme_font_size_override("font_size", 34)
	popup_pick_button.add_theme_color_override("font_color", Color(0.1, 0.85, 0.25))
	popup_pick_button.pressed.connect(_on_popup_pick_pressed)
	champion_popup.add_child(popup_pick_button)

	popup_ban_button = Button.new()
	popup_ban_button.position = Vector2(367, 840)
	popup_ban_button.size = Vector2(235, 95)
	popup_ban_button.text = "BAN"
	popup_ban_button.add_theme_font_size_override("font_size", 34)
	popup_ban_button.add_theme_color_override("font_color", Color(1, 0.15, 0.15))
	popup_ban_button.pressed.connect(_on_popup_ban_pressed)
	champion_popup.add_child(popup_ban_button)

	popup_back_button = Button.new()
	popup_back_button.position = Vector2(640, 840)
	popup_back_button.size = Vector2(235, 95)
	popup_back_button.text = "BACK"
	popup_back_button.add_theme_font_size_override("font_size", 34)
	popup_back_button.pressed.connect(_close_champion_popup)
	champion_popup.add_child(popup_back_button)

func _build_match_ui() -> void:
	match_panel = Panel.new()
	match_panel.position = Vector2(35, 250)
	match_panel.size = Vector2(1010, 1360)
	match_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.01, 0.012, 0.018, 0.9)))
	add_child(match_panel)

	match_time_label = Label.new()
	match_time_label.position = Vector2(385, 265)
	match_time_label.size = Vector2(310, 45)
	match_time_label.add_theme_font_size_override("font_size", 30)
	match_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(match_time_label)

	var speed_tabs: HBoxContainer = HBoxContainer.new()
	speed_tabs.position = Vector2(815, 265)
	speed_tabs.size = Vector2(210, 44)
	speed_tabs.add_theme_constant_override("separation", 8)
	add_child(speed_tabs)

	for speed in [1, 2, 3]:
		var speed_button: Button = Button.new()
		speed_button.text = "x%d" % speed
		speed_button.custom_minimum_size = Vector2(62, 40)
		speed_button.add_theme_font_size_override("font_size", 20)
		speed_button.pressed.connect(_on_match_speed_pressed.bind(float(speed)))
		speed_tabs.add_child(speed_button)
		match_speed_buttons[float(speed)] = speed_button

	var advantage_graph_script = load(ADVANTAGE_GRAPH_SCRIPT)
	if advantage_graph_script == null:
		push_error("Missing match advantage graph script: %s" % ADVANTAGE_GRAPH_SCRIPT)
		return
	advantage_graph = advantage_graph_script.new()
	advantage_graph.position = Vector2(215, 315)
	advantage_graph.size = Vector2(650, 165)
	add_child(advantage_graph)

	player_total_gold_label = Label.new()
	player_total_gold_label.position = Vector2(65, 350)
	player_total_gold_label.size = Vector2(180, 45)
	player_total_gold_label.add_theme_font_size_override("font_size", 24)
	player_total_gold_label.add_theme_color_override("font_color", Color(0.1, 0.9, 0.28))
	add_child(player_total_gold_label)

	ai_total_gold_label = Label.new()
	ai_total_gold_label.position = Vector2(835, 350)
	ai_total_gold_label.size = Vector2(180, 45)
	ai_total_gold_label.add_theme_font_size_override("font_size", 24)
	ai_total_gold_label.add_theme_color_override("font_color", Color(1.0, 0.18, 0.18))
	ai_total_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ai_total_gold_label)

	match_status_label = Label.new()
	match_status_label.position = Vector2(80, 500)
	match_status_label.size = Vector2(920, 45)
	match_status_label.add_theme_font_size_override("font_size", 28)
	match_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(match_status_label)

	for i in range(ROLES.size()):
		var role: String = ROLES[i]
		var y: int = 575 + i * 155
		match_rows["player"][role] = _create_match_player_row("player", role, Vector2(55, y))
		match_rows["ai"][role] = _create_match_player_row("ai", role, Vector2(655, y))

		var diff := Label.new()
		diff.position = Vector2(450, y + 45)
		diff.size = Vector2(180, 50)
		diff.add_theme_font_size_override("font_size", 30)
		diff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		diff.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(diff)
		lane_diff_labels[role] = diff

	event_log_label = Label.new()
	event_log_label.position = Vector2(80, 1380)
	event_log_label.size = Vector2(920, 180)
	event_log_label.add_theme_font_size_override("font_size", 22)
	event_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(event_log_label)

func _create_match_player_row(side: String, role: String, pos: Vector2) -> Dictionary:
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(370, 135)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.045, 0.06, 0.88)))
	add_child(panel)

	var champion_image := TextureRect.new()
	champion_image.position = pos + Vector2(8, 12)
	champion_image.size = Vector2(92, 92)
	champion_image.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	champion_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(champion_image)

	var pseudo := Label.new()
	pseudo.position = pos + Vector2(108, 8)
	pseudo.size = Vector2(245, 28)
	pseudo.add_theme_font_size_override("font_size", 22)
	add_child(pseudo)

	var kda := Label.new()
	kda.position = pos + Vector2(108, 38)
	kda.size = Vector2(120, 26)
	kda.add_theme_font_size_override("font_size", 20)
	add_child(kda)

	var gold := Label.new()
	gold.position = pos + Vector2(228, 38)
	gold.size = Vector2(120, 26)
	gold.add_theme_font_size_override("font_size", 20)
	add_child(gold)

	var level := Label.new()
	level.position = pos + Vector2(108, 66)
	level.size = Vector2(100, 26)
	level.add_theme_font_size_override("font_size", 20)
	add_child(level)

	var status := Label.new()
	status.position = pos + Vector2(208, 66)
	status.size = Vector2(140, 26)
	status.add_theme_font_size_override("font_size", 20)
	add_child(status)

	var item_slots: Array[TextureRect] = []
	for i in range(7):
		var slot := TextureRect.new()
		slot.position = pos + Vector2(108 + i * 34, 98)
		slot.size = Vector2(30, 30)
		slot.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(slot)
		item_slots.append(slot)

	return {
		"panel": panel,
		"champion_image": champion_image,
		"pseudo": pseudo,
		"kda": kda,
		"gold": gold,
		"level": level,
		"status": status,
		"items": item_slots,
	}

func _set_draft_ui_visible(is_visible: bool) -> void:
	if phase_label != null:
		draft_panel.visible = is_visible
		grid_panel.visible = is_visible
		phase_label.visible = is_visible
		timer_label.visible = is_visible
		role_tabs.visible = is_visible
		player_summary_label.visible = is_visible
		ai_summary_label.visible = is_visible
		$champion_scroll.visible = is_visible
		if not is_visible:
			champion_popup.visible = false

func _set_match_ui_visible(is_visible: bool) -> void:
	if match_panel == null:
		return
	match_panel.visible = is_visible
	match_time_label.visible = is_visible
	for key in match_speed_buttons:
		var button: Button = match_speed_buttons[key]
		button.visible = is_visible
	advantage_graph.visible = is_visible
	player_total_gold_label.visible = is_visible
	ai_total_gold_label.visible = is_visible
	match_status_label.visible = is_visible
	event_log_label.visible = is_visible
	for role in ROLES:
		lane_diff_labels[role].visible = is_visible
		for side in ["player", "ai"]:
			for node in match_rows[side][role].values():
				if typeof(node) == TYPE_ARRAY:
					for slot in node:
						slot.visible = is_visible
				else:
					node.visible = is_visible

func _on_search_match_pressed() -> void:
	if ai_clubs.is_empty():
		opponent_club_label.text = "NO AI CLUB"
		return

	search_button.disabled = true
	search_button.text = "SEARCHING..."

	var final_club: Dictionary = ai_clubs[randi() % ai_clubs.size()]
	opponent_ai_club_id = str(final_club.get("id", ""))
	for i in range(22):
		var rolling_club: Dictionary = ai_clubs[i % ai_clubs.size()]
		opponent_club_label.text = str(rolling_club.get("name", "AI CLUB"))
		await get_tree().create_timer(0.07 + float(i) * 0.008).timeout

	opponent_club_label.text = str(final_club.get("name", "AI CLUB"))
	search_button.visible = false
	_start_draft()

func _start_draft() -> void:
	draft_running = true
	current_step = -1
	turn_time_left = float(TURN_SECONDS)
	banned_champions.clear()
	player_picks.clear()
	ai_picks.clear()
	_set_draft_ui_visible(true)
	_next_draft_step()

func _next_draft_step() -> void:
	current_step += 1
	champion_popup.visible = false
	if current_step >= draft_steps.size():
		draft_running = false
		phase_label.text = "DRAFT COMPLETE"
		timer_label.text = ""
		_refresh_draft_summaries()
		_refresh_champion_grid()
		_start_match()
		return

	turn_time_left = float(TURN_SECONDS)
	_update_phase_labels()
	_refresh_draft_summaries()
	_refresh_champion_grid()

	if not _is_player_turn():
		_resolve_ai_turn()

func _resolve_ai_turn() -> void:
	if resolving_ai_turn:
		return

	resolving_ai_turn = true
	await get_tree().create_timer(0.8).timeout

	var step := _current_step()
	var action := str(step.get("action", ""))
	var champion_id := _random_available_champion()
	if champion_id.is_empty():
		resolving_ai_turn = false
		_next_draft_step()
		return

	if action == "ban":
		banned_champions.append(champion_id)
	else:
		ai_picks.append(champion_id)

	resolving_ai_turn = false
	_next_draft_step()

func _on_role_tab_pressed(role: String) -> void:
	selected_role = role
	_refresh_champion_grid()

func _refresh_champion_grid() -> void:
	if champion_grid == null:
		return

	for child in champion_grid.get_children():
		child.queue_free()

	var role_champions: Array = champions_by_role.get(selected_role, [])
	for champion_id in role_champions:
		var champion_key := str(champion_id)
		var champion: Dictionary = champions[champion_key]
		var button := Button.new()
		button.custom_minimum_size = Vector2(168, 190)
		button.text = ""
		button.tooltip_text = str(champion.get("name", "UNKNOWN"))
		button.icon = load(str(champion.get("image", "")))
		button.expand_icon = true
		button.disabled = _is_champion_locked(champion_key)
		button.pressed.connect(_open_champion_popup.bind(champion_key))
		champion_grid.add_child(button)

func _open_champion_popup(champion_id: String) -> void:
	if _is_champion_locked(champion_id):
		return

	popup_champion_id = champion_id
	var champion: Dictionary = champions[champion_id]
	var stats: Dictionary = champion.get("base_stats", {})
	popup_image.texture = load(str(champion.get("image", "")))
	popup_info.text = "%s\nCLASS: %s\nDAMAGE: %s\n\nHP %s | MANA %s\nAD %s | AP %s\nARMOR %s | MR %s\nAS %s | MS %s" % [
		str(champion.get("name", "UNKNOWN")).to_upper(),
		str(champion.get("class", "")).to_upper(),
		str(champion.get("damage_type", "")).to_upper(),
		str(stats.get("health", "-")),
		str(stats.get("mana", "-")),
		str(stats.get("attack_damage", "-")),
		str(stats.get("ability_power", "-")),
		str(stats.get("armor", "-")),
		str(stats.get("magic_resist", "-")),
		str(stats.get("attack_speed", "-")),
		str(stats.get("move_speed", "-")),
	]

	var step := _current_step()
	var action := str(step.get("action", ""))
	var player_turn := _is_player_turn()
	popup_pick_button.disabled = not player_turn or action != "pick"
	popup_ban_button.disabled = not player_turn or action != "ban"
	champion_popup.visible = true

func _close_champion_popup() -> void:
	champion_popup.visible = false
	popup_champion_id = ""

func _on_popup_pick_pressed() -> void:
	_apply_player_action("pick", popup_champion_id)

func _on_popup_ban_pressed() -> void:
	_apply_player_action("ban", popup_champion_id)

func _apply_player_action(action: String, champion_id: String) -> void:
	if not _is_player_turn() or champion_id.is_empty() or _is_champion_locked(champion_id):
		return

	var step := _current_step()
	if str(step.get("action", "")) != action:
		return

	if action == "ban":
		banned_champions.append(champion_id)
	else:
		player_picks.append(champion_id)

	_next_draft_step()

func _auto_pick_for_player() -> void:
	var step := _current_step()
	var action := str(step.get("action", ""))
	var champion_id := _random_available_champion()
	if champion_id.is_empty():
		_next_draft_step()
		return

	if action == "ban":
		banned_champions.append(champion_id)
	else:
		player_picks.append(champion_id)

	_next_draft_step()

func _current_step() -> Dictionary:
	if current_step < 0 or current_step >= draft_steps.size():
		return {}
	return draft_steps[current_step]

func _is_player_turn() -> bool:
	var step := _current_step()
	return str(step.get("actor", "")) == "player"

func _is_champion_locked(champion_id: String) -> bool:
	return banned_champions.has(champion_id) or player_picks.has(champion_id) or ai_picks.has(champion_id)

func _random_available_champion() -> String:
	var available: Array[String] = []
	for champion_id in champions:
		var champion_key := str(champion_id)
		if not _is_champion_locked(champion_key):
			available.append(champion_key)

	if available.is_empty():
		return ""

	return available[randi() % available.size()]

func _update_phase_labels() -> void:
	if not draft_running:
		return

	var step := _current_step()
	var actor := str(step.get("actor", "")).to_upper()
	var action := str(step.get("action", "")).to_upper()
	phase_label.text = "%s %s" % [actor, action]
	timer_label.text = "TIME: %02d" % max(0, int(ceil(turn_time_left)))

func _refresh_draft_summaries() -> void:
	player_summary_label.text = "YOUR PICKS: %s\nBANS: %s" % [
		_names_for_ids(player_picks),
		_names_for_ids(_player_bans()),
	]
	ai_summary_label.text = "AI PICKS: %s\nBANS: %s" % [
		_names_for_ids(ai_picks),
		_names_for_ids(_ai_bans()),
	]

func _player_bans() -> Array[String]:
	var result: Array[String] = []
	for i in range(banned_champions.size()):
		if i % 2 == 0:
			result.append(banned_champions[i])
	return result

func _ai_bans() -> Array[String]:
	var result: Array[String] = []
	for i in range(banned_champions.size()):
		if i % 2 == 1:
			result.append(banned_champions[i])
	return result

func _names_for_ids(ids: Array[String]) -> String:
	if ids.is_empty():
		return "-"

	var names: Array[String] = []
	for champion_id in ids:
		if champions.has(champion_id):
			var champion: Dictionary = champions[champion_id]
			names.append(str(champion.get("name", champion_id)))

	return ", ".join(names)

func _start_match() -> void:
	await get_tree().create_timer(1.0).timeout
	_set_draft_ui_visible(false)
	$title_label.text = "LIVE MATCH"
	player_club_label.position = Vector2(60, 185)
	opponent_club_label.position = Vector2(620, 185)
	$vs_label.position = Vector2(465, 185)

	var player_players := GameData.get_players_for_club(player_club_id)
	var ai_players := GameData.get_players_for_club(opponent_ai_club_id)
	var match_sim_script = load(MATCH_SIM_SCRIPT)
	if match_sim_script == null:
		push_error("Missing match simulation script: %s" % MATCH_SIM_SCRIPT)
		return
	match_sim = match_sim_script.new()
	match_sim.setup(player_players, ai_players, player_picks, ai_picks, champions, items)
	match_running = true
	_set_match_speed(1.0)
	_set_match_ui_visible(true)
	_refresh_match_ui()

func _on_match_speed_pressed(speed: float) -> void:
	_set_match_speed(speed)

func _set_match_speed(speed: float) -> void:
	match_speed = speed
	for key in match_speed_buttons:
		var button: Button = match_speed_buttons[key]
		var is_selected: bool = is_equal_approx(float(key), match_speed)
		button.disabled = is_selected
		button.add_theme_color_override("font_color", Color(0.1, 0.9, 0.28) if is_selected else Color.WHITE)
		button.add_theme_color_override("font_disabled_color", Color(0.1, 0.9, 0.28))
		button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.12, 0.15, 0.1, 0.95) if is_selected else Color(0.04, 0.045, 0.06, 0.95)))
		button.add_theme_stylebox_override("hover", _make_panel_style(Color(0.16, 0.19, 0.13, 1.0)))
		button.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.18, 0.22, 0.14, 1.0)))
		button.add_theme_stylebox_override("disabled", _make_panel_style(Color(0.12, 0.15, 0.1, 0.95)))

func _refresh_match_ui() -> void:
	if match_sim == null:
		return

	var snapshot: Dictionary = match_sim.get_snapshot()
	var game_time := float(snapshot.get("time", 0.0))
	var minutes := int(game_time) / 60
	var seconds := int(game_time) % 60
	match_time_label.text = "%02d:%02d" % [minutes, seconds]

	var diff := int(snapshot.get("gold_diff", 0))
	advantage_graph.set_gold_history(snapshot.get("gold_history", []), diff)

	var teams: Dictionary = snapshot.get("teams", {})
	player_total_gold_label.text = "%d G" % _team_gold_from_snapshot(teams, "player")
	ai_total_gold_label.text = "%d G" % _team_gold_from_snapshot(teams, "ai")

	var winner := str(snapshot.get("winner", ""))
	if winner.is_empty():
		match_status_label.text = "MATCH IN PROGRESS"
	else:
		match_status_label.text = "%s WINS" % winner.to_upper()
		match_running = false

	for role in ROLES:
		_refresh_match_row("player", role, teams["player"][role])
		_refresh_match_row("ai", role, teams["ai"][role])
		var lane_diff: int = int(teams["player"][role].get("gold", 0)) - int(teams["ai"][role].get("gold", 0))
		var label: Label = lane_diff_labels[role]
		label.text = "%s\n%+d" % [role.to_upper(), lane_diff]
		label.add_theme_color_override("font_color", Color(0.1, 0.9, 0.28) if lane_diff >= 0 else Color(1.0, 0.18, 0.18))

	var events: Array = snapshot.get("events", [])
	event_log_label.text = "\n".join(events)

func _refresh_match_row(side: String, role: String, state: Dictionary) -> void:
	var row: Dictionary = match_rows[side][role]
	var champion: Dictionary = state.get("champion", {})
	var image: TextureRect = row["champion_image"]
	image.texture = load(str(champion.get("image", "")))
	image.modulate = Color(1, 1, 1, 1) if bool(state.get("alive", true)) else Color(0.28, 0.28, 0.28, 1)

	var pseudo: Label = row["pseudo"]
	pseudo.text = str(state.get("pseudo", "PLAYER"))
	var kda: Label = row["kda"]
	kda.text = "%d/%d/%d" % [int(state.get("kills", 0)), int(state.get("deaths", 0)), int(state.get("assists", 0))]
	var gold_label: Label = row["gold"]
	gold_label.text = "%d G" % int(state.get("gold", 0))
	var level: Label = row["level"]
	level.text = "LVL %d" % int(state.get("level", 1))
	var status: Label = row["status"]
	if bool(state.get("alive", true)):
		status.text = "ALIVE"
		status.add_theme_color_override("font_color", Color(0.1, 0.9, 0.28))
	else:
		status.text = "DEAD"
		status.add_theme_color_override("font_color", Color(1.0, 0.18, 0.18))

	var item_ids: Array = state.get("items", [])
	var slots: Array = row["items"]
	for i in range(slots.size()):
		var slot: TextureRect = slots[i]
		if i < item_ids.size() and items.has(item_ids[i]):
			var item: Dictionary = items[item_ids[i]]
			slot.texture = load(str(item.get("icon", "")))
		else:
			slot.texture = null

func _team_gold_from_snapshot(teams: Dictionary, side: String) -> int:
	var total := 0
	if not teams.has(side):
		return total
	for role in ROLES:
		total += int(teams[side][role].get("gold", 0))
	return total

func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed

	return {}

func _make_panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.85, 0.78, 0.35, 0.9)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	return style

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
