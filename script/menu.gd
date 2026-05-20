extends Control

const TEAM_SCENE := "res://scene/teamsquad.tscn"

@onready var account_label: Label = $account_label
@onready var team_button: Button = $TEAM

func _ready() -> void:
	team_button.pressed.connect(_on_team_pressed)

	var email := str(get_tree().get_meta("current_user_email", ""))
	if email.is_empty():
		account_label.text = "NOT CONNECTED"
	else:
		account_label.text = "CONNECTED: " + email

func _on_team_pressed() -> void:
	get_tree().change_scene_to_file(TEAM_SCENE)
	
