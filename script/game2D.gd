extends Control

const GameData = preload("res://script/game_data.gd")
const MATCH_SIM_SCRIPT := "res://script/match_sim.gd"
const CHAMPIONS_FILE := "res://data/champions.json"
const ITEMS_FILE := "res://data/items.json"
const GAME_SCENE := "res://scene/game.tscn"
const MENU_SCENE := "res://scene/menu.tscn"

@onready var map_view: Control = $map_view
@onready var time_label: Label = $top_bar/time_label
@onready var gold_label: Label = $top_bar/gold_label
@onready var state_label: Label = $top_bar/state_label
@onready var objective_label: Label = $top_bar/objective_label
@onready var event_log_label: Label = $event_log_label
@onready var player_state_panel: Panel = $player_state_panel
@onready var blue_state_label: RichTextLabel = $player_state_panel/blue_state_label
@onready var red_state_label: RichTextLabel = $player_state_panel/red_state_label
@onready var live_button: Button = $live_button
@onready var menu_button: Button = $menu_button

var match_sim
var match_running: bool = false
var match_speed: float = 1.0
var speed_buttons: Dictionary = {}

func _ready() -> void:
	randomize()
	live_button.pressed.connect(_on_live_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	_bind_speed_buttons()
	_apply_styles()
	_start_or_restore_match()

func _process(delta: float) -> void:
	if match_sim == null or not match_running:
		return
	var match_delta: float = delta * match_speed
	match_sim.step(match_delta)
	_refresh_map(match_delta)

func _start_or_restore_match() -> void:
	if get_tree().has_meta("current_match_sim"):
		match_sim = get_tree().get_meta("current_match_sim")
		match_running = true
		_set_match_speed(float(get_tree().get_meta("current_match_speed", 1.0)))
		_refresh_map(0.0)
		return

	var data: Dictionary = get_tree().get_meta("current_match_data", {})
	var player_club_id: String = str(data.get("player_club_id", ""))
	var opponent_ai_club_id: String = str(data.get("opponent_ai_club_id", ""))
	var player_picks: Array[String] = _string_array(data.get("player_picks", []))
	var ai_picks: Array[String] = _string_array(data.get("ai_picks", []))
	var champions: Dictionary = _read_json_file(CHAMPIONS_FILE)
	var items: Dictionary = _read_json_file(ITEMS_FILE)
	var player_players: Dictionary = GameData.get_players_for_club(player_club_id)
	var ai_players: Dictionary = GameData.get_players_for_club(opponent_ai_club_id)
	var match_sim_script = load(MATCH_SIM_SCRIPT)
	if match_sim_script == null:
		push_error("Missing match simulation script: %s" % MATCH_SIM_SCRIPT)
		return
	match_sim = match_sim_script.new()
	match_sim.setup(player_players, ai_players, player_picks, ai_picks, champions, items)
	get_tree().set_meta("current_match_sim", match_sim)
	match_running = true
	_set_match_speed(1.0)
	_refresh_map(0.0)

func _refresh_map(visual_delta: float) -> void:
	var snapshot: Dictionary = match_sim.get_snapshot()
	var game_time: float = float(snapshot.get("time", 0.0))
	var minutes: int = int(game_time) / 60
	var seconds: int = int(game_time) % 60
	time_label.text = "%02d:%02d" % [minutes, seconds]

	var gold_diff: int = int(snapshot.get("gold_diff", 0))
	if gold_diff > 0:
		gold_label.text = "+%d GOLD" % gold_diff
		gold_label.add_theme_color_override("font_color", Color(0.1, 0.9, 0.28))
	elif gold_diff < 0:
		gold_label.text = "%d GOLD" % gold_diff
		gold_label.add_theme_color_override("font_color", Color(1.0, 0.18, 0.18))
	else:
		gold_label.text = "EVEN GOLD"
		gold_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.25))

	var winner: String = str(snapshot.get("winner", ""))
	if winner.is_empty():
		state_label.text = "LIVE 2D MAP"
	else:
		state_label.text = "%s WINS" % winner.to_upper()
		match_running = false

	var events: Array = snapshot.get("events", [])
	event_log_label.text = "\n".join(_display_events(events))
	_refresh_objective_label(snapshot)
	_refresh_player_state_table(snapshot.get("teams", {}))
	if map_view.has_method("update_from_snapshot"):
		map_view.update_from_snapshot(snapshot, maxf(visual_delta, 0.016))

func _refresh_player_state_table(teams: Dictionary) -> void:
	blue_state_label.text = _side_state_text(teams, "player", "BLUE")
	red_state_label.text = _side_state_text(teams, "ai", "RED")

func _side_state_text(teams: Dictionary, side: String, title: String) -> String:
	var lines: Array[String] = ["[b]%s ALIVE[/b]" % title]
	if not teams.has(side):
		return "\n".join(lines)
	for role in ["top", "jgl", "mid", "bot", "sup"]:
		var state: Dictionary = teams[side][role]
		var champion: Dictionary = state.get("champion", {})
		var alive: bool = bool(state.get("alive", true))
		var status: String = "Alive" if alive else "Dead %ds" % int(ceil(float(state.get("death_timer", 0.0))))
		var color: String = "#33e65a" if alive else "#ff4444"
		lines.append("[color=%s]%s %s / %s : %s[/color]" % [
			color,
			role.to_upper(),
			str(state.get("pseudo", "PLAYER")),
			str(champion.get("name", "Champion")),
			status,
		])
	return "\n".join(lines)

func _refresh_objective_label(snapshot: Dictionary) -> void:
	var drakes: Dictionary = snapshot.get("drakes", {})
	var nashors: Dictionary = snapshot.get("nashors", {})
	objective_label.text = "BLUE  DRAKE %d  NASH %d        RED  DRAKE %d  NASH %d" % [
		int(drakes.get("player", 0)),
		int(nashors.get("player", 0)),
		int(drakes.get("ai", 0)),
		int(nashors.get("ai", 0)),
	]

func _display_events(events: Array) -> Array[String]:
	var result: Array[String] = []
	for event in events:
		var text: String = str(event)
		if text.begins_with("KILL|"):
			var parts: PackedStringArray = text.split("|")
			if parts.size() >= 5:
				result.append("%s killed %s" % [parts[2], parts[4]])
			else:
				result.append(text)
		else:
			result.append(text)
	return result

func _bind_speed_buttons() -> void:
	for speed in [1, 2, 3, 5]:
		var button: Button = get_node("top_bar/speed_tabs/speed_%d" % speed) as Button
		button.pressed.connect(_on_speed_pressed.bind(float(speed)))
		speed_buttons[float(speed)] = button

func _on_speed_pressed(speed: float) -> void:
	_set_match_speed(speed)

func _set_match_speed(speed: float) -> void:
	match_speed = speed
	get_tree().set_meta("current_match_speed", match_speed)
	for key in speed_buttons:
		var button: Button = speed_buttons[key]
		var selected: bool = is_equal_approx(float(key), match_speed)
		button.disabled = selected
		button.add_theme_color_override("font_color", Color(0.1, 0.9, 0.28) if selected else Color.WHITE)
		button.add_theme_color_override("font_disabled_color", Color(0.1, 0.9, 0.28))
		button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.12, 0.15, 0.1, 0.95) if selected else Color(0.04, 0.045, 0.06, 0.95)))
		button.add_theme_stylebox_override("disabled", _make_panel_style(Color(0.12, 0.15, 0.1, 0.95)))

func _apply_styles() -> void:
	var top_bar: Panel = $top_bar as Panel
	top_bar.add_theme_stylebox_override("panel", _make_panel_style(Color(0.01, 0.012, 0.018, 0.92)))
	player_state_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.01, 0.012, 0.018, 0.88)))
	live_button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.04, 0.045, 0.06, 0.95)))
	menu_button.add_theme_stylebox_override("normal", _make_panel_style(Color(0.04, 0.045, 0.06, 0.95)))

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

func _make_panel_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
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
	return style

func _on_live_pressed() -> void:
	if match_sim != null:
		get_tree().set_meta("current_match_sim", match_sim)
	get_tree().set_meta("current_match_speed", match_speed)
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
