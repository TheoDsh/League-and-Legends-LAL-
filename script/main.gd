extends Control

const GameData = preload("res://script/game_data.gd")
const MENU_SCENE := "res://scene/menu.tscn"
const CLUB_CREATION_SCENE := "res://scene/creation_du_club.tscn"
const MIN_PASSWORD_LENGTH := 4

@onready var email_input: LineEdit = $emailinput
@onready var password_input: LineEdit = $passwordinput
@onready var error_label: Label = $error_label

var email_regex := RegEx.new()

func _ready() -> void:
	randomize()
	GameData.sync_ai_debug_data_to_user_storage()
	email_regex.compile("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
	$login.pressed.connect(_on_login_pressed)
	$register.pressed.connect(_on_register_pressed)

func _on_login_pressed() -> void:
	var email := email_input.text.strip_edges().to_lower()
	var password := password_input.text

	if not _validate_inputs(email, password):
		return

	var users := GameData.load_users()
	if not users.has(email):
		error_label.text = "NO ACCOUNT"
		return

	var user: Dictionary = users[email]
	var salt := str(user.get("salt", ""))
	var saved_hash := str(user.get("password_hash", ""))
	var password_hash := _hash_password(password, salt)

	if password_hash != saved_hash:
		error_label.text = "WRONG PASSWORD"
		return

	get_tree().set_meta("current_user_email", email)
	if str(user.get("club_id", "")).is_empty():
		get_tree().change_scene_to_file(CLUB_CREATION_SCENE)
	else:
		get_tree().change_scene_to_file(MENU_SCENE)

func _on_register_pressed() -> void:
	var email := email_input.text.strip_edges().to_lower()
	var password := password_input.text

	if not _validate_inputs(email, password):
		return

	var users := GameData.load_users()
	if users.has(email):
		error_label.text = "ACCOUNT EXISTS"
		return

	var salt := _make_salt()
	users[email] = {
		"salt": salt,
		"password_hash": _hash_password(password, salt),
		"club_id": "",
	}
	GameData.save_users(users)

	get_tree().set_meta("current_user_email", email)
	get_tree().change_scene_to_file(CLUB_CREATION_SCENE)

func _validate_inputs(email: String, password: String) -> bool:
	if not _is_valid_email(email):
		error_label.text = "EMAIL INVALID"
		return false

	if password.length() < MIN_PASSWORD_LENGTH:
		error_label.text = "PASSWORD TOO SHORT"
		return false

	return true

func _is_valid_email(email: String) -> bool:
	return email_regex.search(email) != null

func _make_salt() -> String:
	return str(Time.get_unix_time_from_system()) + "_" + str(randi())

func _hash_password(password: String, salt: String) -> String:
	return (salt + password).sha256_text()
