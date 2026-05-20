extends Control

const GameData = preload("res://script/game_data.gd")
const PLAYER_DETAIL_SCENE := "res://scene/player_detail.tscn"
const MENU_SCENE := "res://scene/menu.tscn"

const ROLE_ORDER := ["top", "jgl", "mid", "bot", "sup"]

@onready var back_button: Button = $fond_menu/back_button

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_build_team_list()

func _build_team_list() -> void:
	var email := str(get_tree().get_meta("current_user_email", ""))
	var club_id := GameData.get_user_club_id(email)
	var players := GameData.get_players_for_club(club_id)

	var y := 300
	for role in ROLE_ORDER:
		for player_id in players:
			var player: Dictionary = players[player_id]
			if str(player.get("role", "")) != role:
				continue

			_add_player_row(player_id, player, y)
			y += 170
			break

func _add_player_row(player_id: String, player: Dictionary, y: int) -> void:
	var role_label := Label.new()
	role_label.position = Vector2(90, y + 35)
	role_label.size = Vector2(160, 70)
	role_label.text = str(player.get("role", "")).to_upper()
	role_label.add_theme_font_size_override("font_size", 42)
	role_label.add_theme_color_override("font_color", Color(0.8745098, 0.8745098, 0.13333334, 1))
	add_child(role_label)

	var name_label := Label.new()
	name_label.position = Vector2(260, y + 35)
	name_label.size = Vector2(360, 70)
	name_label.text = str(player.get("pseudo", "UNKNOWN"))
	name_label.add_theme_font_size_override("font_size", 36)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(name_label)

	var portrait := TextureButton.new()
	portrait.position = Vector2(740, y)
	portrait.size = Vector2(128, 128)
	portrait.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_path := str(player.get("portrait", ""))
	if not portrait_path.is_empty():
		portrait.texture_normal = load(portrait_path)
	portrait.pressed.connect(_on_player_pressed.bind(player_id))
	add_child(portrait)

	var details_button := Button.new()
	details_button.position = Vector2(890, y + 25)
	details_button.size = Vector2(150, 80)
	details_button.text = "VIEW"
	details_button.pressed.connect(_on_player_pressed.bind(player_id))
	add_child(details_button)

func _on_player_pressed(player_id: String) -> void:
	get_tree().set_meta("current_player_id", player_id)
	get_tree().change_scene_to_file(PLAYER_DETAIL_SCENE)
	
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
