extends Control

const USERS_FILE := "user://users.json"
const USERS_DEBUG_COPY_FILE := "res://data/users.json"
const MENU_SCENE := "res://scene/menu.tscn"
const MIN_PASSWORD_LENGTH := 4
const PLAYER_ROLES := ["top", "jgl", "mid", "bot", "sup"]
const PSEUDO_PREFIXES := [
	"Neo",
	"Sky",
	"Zen",
	"Nova",
	"Riven",
	"Shadow",
	"Storm",
	"Ace",
	"Zero",
	"Vex",
	"Kai",
	"Rogue",
]
const PSEUDO_SUFFIXES := [
	"Blade",
	"Pulse",
	"Fang",
	"Rush",
	"Wave",
	"Spark",
	"King",
	"Fox",
	"Prime",
	"Arrow",
	"Storm",
	"Knight",
]

@onready var email_input: LineEdit = $emailinput
@onready var password_input: LineEdit = $passwordinput
@onready var error_label: Label = $error_label

var email_regex := RegEx.new()

func _ready() -> void:
	randomize()
	email_regex.compile("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
	$login.pressed.connect(_on_login_pressed)
	$register.pressed.connect(_on_register_pressed)

func _on_login_pressed() -> void:
	var email := email_input.text.strip_edges().to_lower()
	var password := password_input.text

	if not _validate_inputs(email, password):
		return

	var users := _load_users()

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

	if not user.has("players"):
		user["players"] = _generate_starter_players()
		users[email] = user
		_save_users(users)

	error_label.text = "LOGIN OK"
	_go_to_menu(email)

func _on_register_pressed() -> void:
	var email := email_input.text.strip_edges().to_lower()
	var password := password_input.text

	if not _validate_inputs(email, password):
		return

	var users := _load_users()
	if users.has(email):
		error_label.text = "ACCOUNT EXISTS"
		return

	var salt := _make_salt()
	users[email] = {
		"salt": salt,
		"password_hash": _hash_password(password, salt),
		"players": _generate_starter_players(),
	}
	_save_users(users)
	error_label.text = "ACCOUNT CREATED"
	_go_to_menu(email)

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

func _load_users() -> Dictionary:
	if not FileAccess.file_exists(USERS_FILE):
		return _load_debug_users_copy()

	var file := FileAccess.open(USERS_FILE, FileAccess.READ)
	if file == null:
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed

	return {}

func _save_users(users: Dictionary) -> void:
	var file := FileAccess.open(USERS_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(users, "\t"))

	var debug_file := FileAccess.open(USERS_DEBUG_COPY_FILE, FileAccess.WRITE)
	if debug_file != null:
		debug_file.store_string(JSON.stringify(users, "\t"))

func _load_debug_users_copy() -> Dictionary:
	if not FileAccess.file_exists(USERS_DEBUG_COPY_FILE):
		return {}

	var file := FileAccess.open(USERS_DEBUG_COPY_FILE, FileAccess.READ)
	if file == null:
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed

	return {}

func _make_salt() -> String:
	return str(Time.get_unix_time_from_system()) + "_" + str(randi())

func _hash_password(password: String, salt: String) -> String:
	return (salt + password).sha256_text()

func _generate_starter_players() -> Array:
	var starter_players := []
	var used_pseudos := {}

	for role in PLAYER_ROLES:
		var pseudo := _generate_unique_pseudo(used_pseudos)
		starter_players.append({
			"pseudo": pseudo,
			"role": role,
			"level": 1,
		})

	return starter_players

func _generate_unique_pseudo(used_pseudos: Dictionary) -> String:
	var pseudo := _generate_pseudo()
	while used_pseudos.has(pseudo):
		pseudo = _generate_pseudo()

	used_pseudos[pseudo] = true
	return pseudo

func _generate_pseudo() -> String:
	var prefix := PSEUDO_PREFIXES.pick_random()
	var suffix := PSEUDO_SUFFIXES.pick_random()
	var number := randi_range(10, 99)
	return "%s%s%d" % [prefix, suffix, number]

func _go_to_menu(email: String) -> void:
	get_tree().set_meta("current_user_email", email)
	get_tree().change_scene_to_file(MENU_SCENE)
