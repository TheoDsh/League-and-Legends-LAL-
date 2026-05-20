extends Control

const GameData = preload("res://script/game_data.gd")
const MATCH_SIM_SCRIPT := "res://script/match_sim.gd"
const CHAMPIONS_FILE := "res://data/champions.json"
const ITEMS_FILE := "res://data/items.json"
const MENU_SCENE := "res://scene/menu.tscn"
const ROLES: Array[String] = ["top", "jgl", "mid", "bot", "sup"]

@onready var player_club_label: Label = $player_club_label
@onready var opponent_club_label: Label = $opponent_club_label
@onready var match_time_label: Label = $match_panel/match_time_label
@onready var player_total_gold_label: Label = $match_panel/player_total_gold_label
@onready var ai_total_gold_label: Label = $match_panel/ai_total_gold_label
@onready var match_status_label: Label = $match_panel/match_status_label
@onready var event_log_label: Label = $match_panel/event_log_label
@onready var advantage_graph = $match_panel/advantage_graph
@onready var back_button: Button = $back_button

var champions: Dictionary = {}
var items: Dictionary = {}
var match_sim
var match_running := false
var match_speed := 1.0
var match_speed_buttons: Dictionary = {}
var match_rows: Dictionary = {"player": {}, "ai": {}}
var lane_diff_labels: Dictionary = {}

func _ready() -> void:
	randomize()
	champions = _read_json_file(CHAMPIONS_FILE)
	items = _read_json_file(ITEMS_FILE)
	back_button.pressed.connect(_on_back_pressed)
	_bind_speed_buttons()
	_bind_match_rows()
	_apply_static_styles()
	_start_from_draft_data()

func _process(delta: float) -> void:
	if not match_running or match_sim == null:
		return
	match_sim.step(delta * match_speed)
	_refresh_match_ui()

func _start_from_draft_data() -> void:
	var data: Dictionary = get_tree().get_meta("current_match_data", {})
	var player_club_id := str(data.get("player_club_id", ""))
	var opponent_ai_club_id := str(data.get("opponent_ai_club_id", ""))
	var player_picks: Array[String] = _string_array(data.get("player_picks", []))
	var ai_picks: Array[String] = _string_array(data.get("ai_picks", []))

	var clubs := GameData.load_clubs()
	player_club_label.text = _club_name(clubs, player_club_id, "YOUR CLUB")
	opponent_club_label.text = _club_name(clubs, opponent_ai_club_id, "AI CLUB")

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
	_refresh_match_ui()

func _bind_speed_buttons() -> void:
	for speed in [1, 2, 3, 5]:
		var button := get_node("match_panel/speed_tabs/speed_%d" % speed) as Button
		button.pressed.connect(_on_match_speed_pressed.bind(float(speed)))
		match_speed_buttons[float(speed)] = button

func _bind_match_rows() -> void:
	for role in ROLES:
		match_rows["player"][role] = _make_row_refs(get_node("match_panel/player_%s_row" % role) as Control)
		match_rows["ai"][role] = _make_row_refs(get_node("match_panel/ai_%s_row" % role) as Control)
		lane_diff_labels[role] = get_node("match_panel/%s_diff_label" % role)

func _make_row_refs(row: Control) -> Dictionary:
	var item_slots: Array[TextureRect] = []
	for i in range(7):
		item_slots.append(row.get_node("item_%d" % i) as TextureRect)
	return {
		"panel": row.get_node("panel"),
		"row": row,
		"champion_image": row.get_node("champion_image"),
		"pseudo": row.get_node("pseudo"),
		"kda": row.get_node("kda"),
		"gold": row.get_node("gold"),
		"level": row.get_node("level"),
		"cs": row.get_node("cs"),
		"status": row.get_node("status"),
		"items": item_slots,
	}

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
	var cs: Label = row["cs"]
	cs.text = "CS %d" % int(state.get("cs", 0))
	var status: Label = row["status"]
	if bool(state.get("alive", true)):
		status.text = "OK"
		status.add_theme_color_override("font_color", Color(0.1, 0.9, 0.28))
	else:
		status.text = "%ds" % int(ceil(float(state.get("death_timer", 0.0))))
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

func _club_name(clubs: Dictionary, club_id: String, fallback: String) -> String:
	if clubs.has(club_id) and typeof(clubs[club_id]) == TYPE_DICTIONARY:
		return str(clubs[club_id].get("name", fallback))
	return fallback

func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for entry in value:
		result.append(str(entry))
	return result

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

func _apply_static_styles() -> void:
	var panel := $match_panel as Panel
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.01, 0.012, 0.018, 0.9)))
	for side in ["player", "ai"]:
		for role in ROLES:
			var row: Dictionary = match_rows[side][role]
			var row_panel: Panel = row["panel"]
			row_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.045, 0.06, 0.88)))

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
