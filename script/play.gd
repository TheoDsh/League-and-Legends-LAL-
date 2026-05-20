extends Control

const GameData = preload("res://script/game_data.gd")
const MENU_SCENE := "res://scene/menu.tscn"
const GAME_SCENE := "res://scene/game.tscn"
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
	_set_draft_ui_visible(false)

func _process(delta: float) -> void:
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
	get_tree().set_meta("current_match_data", {
		"player_club_id": player_club_id,
		"opponent_ai_club_id": opponent_ai_club_id,
		"player_picks": player_picks.duplicate(),
		"ai_picks": ai_picks.duplicate(),
	})
	get_tree().change_scene_to_file(GAME_SCENE)

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
