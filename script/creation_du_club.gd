extends Control

const GameData = preload("res://script/game_data.gd")
const MENU_SCENE := "res://scene/menu.tscn"

@onready var club_name_input: LineEdit = $nom_du_club
@onready var accept_button: Button = $accept_club

func _ready() -> void:
	accept_button.pressed.connect(_on_accept_club_pressed)

func _on_accept_club_pressed() -> void:
	var email := str(get_tree().get_meta("current_user_email", ""))
	var club_name := club_name_input.text.strip_edges()

	if email.is_empty():
		return

	if club_name.length() < 3:
		club_name_input.placeholder_text = "MIN 3 CHARACTERES"
		club_name_input.clear()
		return

	GameData.create_club_for_user(email, club_name)
	get_tree().change_scene_to_file(MENU_SCENE)
