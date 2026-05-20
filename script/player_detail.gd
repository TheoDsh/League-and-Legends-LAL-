extends Control

const GameData = preload("res://script/game_data.gd")
const TEAM_SCENE := "res://scene/teamsquad.tscn"

@onready var portrait: TextureRect = $portrait
@onready var info_label: Label = $info_label
@onready var stats_label: Label = $stats_label
@onready var back_button: Button = $back_button

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_show_player()

func _show_player() -> void:
	var player_id := str(get_tree().get_meta("current_player_id", ""))
	var player := GameData.get_player(player_id)
	if player.is_empty():
		info_label.text = "PLAYER NOT FOUND"
		return

	var portrait_path := str(player.get("portrait", ""))
	if not portrait_path.is_empty():
		portrait.texture = load(portrait_path)

	info_label.text = "%s\n%s - %s" % [
		str(player.get("pseudo", "UNKNOWN")),
		str(player.get("role", "")).to_upper(),
		str(player.get("gender", "")).to_upper(),
	]

	var stats := {}
	if typeof(player.get("stats", {})) == TYPE_DICTIONARY:
		stats = player.get("stats", {})
	stats_label.text = "MECHANICS: %s\nLANING: %s\nVISION: %s\nTEAMPLAY: %s\nMENTAL: %s" % [
		str(stats.get("mechanics", "-")),
		str(stats.get("laning", "-")),
		str(stats.get("vision", "-")),
		str(stats.get("teamplay", "-")),
		str(stats.get("mental", "-")),
	]

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(TEAM_SCENE)
