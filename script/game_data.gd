extends RefCounted

const USERS_FILE := "user://users.json"
const USERS_DEBUG_COPY_FILE := "res://data/users.json"
const CLUBS_FILE := "user://clubs.json"
const CLUBS_DEBUG_COPY_FILE := "res://data/clubs.json"
const PLAYERS_FILE := "user://players.json"
const PLAYERS_DEBUG_COPY_FILE := "res://data/players.json"
const PORTRAITS_DIR := "res://FONT & sprite/personnage"

const PLAYER_ROLES := ["top", "jgl", "mid", "bot", "sup"]
const PLAYER_GENDERS := ["male", "female"]
const STAT_GRADES := ["E", "D", "C", "B", "A", "S"]
const PSEUDO_PREFIXES := [
	"Aero", "Aki", "Alpha", "Astro", "Axel", "Neo", "Sky", "Zen",
	"Nova", "Riven", "Shadow", "Storm", "Ace", "Zero", "Vex", "Kai",
	"Rogue", "Blade", "Blitz", "Crimson", "Drift", "Echo", "Frost",
	"Ghost", "Hex", "Iron", "Jade", "Jinx", "Kuro", "Lunar", "Mint",
	"Nexus", "Onyx", "Pixel", "Prime", "Quest", "Rapid", "Solar",
	"Titan", "Ultra", "Venom", "Wild", "Xeno", "Yoru", "Zeta",
]
const PSEUDO_SUFFIXES := [
	"Blade", "Pulse", "Fang", "Rush", "Wave", "Spark", "King", "Fox",
	"Prime", "Arrow", "Storm", "Knight", "Core", "Dash", "Edge",
	"Flare", "Guard", "Hawk", "Ice", "Jumper", "Legend", "Mage",
	"Ninja", "Oracle", "Phantom", "Quest", "Rider", "Strike", "Talon",
	"Unit", "Viper", "Warden", "X", "Yard", "Zone", "Drake", "Nova",
	"Reaper", "Runner", "Saber", "Sniper", "Spirit", "Tank", "Wizard",
]

static func load_users() -> Dictionary:
	return _load_json(USERS_FILE, USERS_DEBUG_COPY_FILE)

static func save_users(users: Dictionary) -> void:
	_save_json(users, USERS_FILE, USERS_DEBUG_COPY_FILE)

static func load_clubs() -> Dictionary:
	return _load_json(CLUBS_FILE, CLUBS_DEBUG_COPY_FILE)

static func save_clubs(clubs: Dictionary) -> void:
	_save_json(clubs, CLUBS_FILE, CLUBS_DEBUG_COPY_FILE)

static func load_players() -> Dictionary:
	var players := _load_json(PLAYERS_FILE, PLAYERS_DEBUG_COPY_FILE)
	if players.is_empty():
		return _read_json_file(PLAYERS_DEBUG_COPY_FILE)
	return players

static func save_players(players: Dictionary) -> void:
	_save_json(players, PLAYERS_FILE, PLAYERS_DEBUG_COPY_FILE)

static func create_club_for_user(email: String, club_name: String) -> String:
	var club_id := make_club_id(email)
	var users := load_users()
	var clubs := load_clubs()
	var players := load_players()

	if not users.has(email):
		return ""

	var user: Dictionary = users[email]
	user["club_id"] = club_id
	users[email] = user
	clubs[club_id] = {
		"name": club_name,
		"type": "player",
		"owner_email": email,
		"money": 1000,
		"reputation": 1,
	}

	_assign_starter_players_to_club(players, club_id)

	save_users(users)
	save_clubs(clubs)
	save_players(players)
	return club_id

static func make_club_id(email: String) -> String:
	var id := "club_"
	for i in range(email.length()):
		var character := email.substr(i, 1).to_lower()
		var code := character.unicode_at(0)
		if code >= 97 and code <= 122:
			id += character
		elif code >= 48 and code <= 57:
			id += character
		else:
			id += "_"
	return id

static func _assign_starter_players_to_club(players: Dictionary, club_id: String) -> void:
	for role in PLAYER_ROLES:
		var player_id := _find_free_player_for_role(players, role)
		if player_id.is_empty():
			player_id = _create_fallback_player(players, role)

		var player: Dictionary = players[player_id]
		player["club_id"] = club_id
		players[player_id] = player

static func _find_free_player_for_role(players: Dictionary, role: String) -> String:
	var matching_ids := []
	for player_id in players:
		var player = players[player_id]
		if typeof(player) != TYPE_DICTIONARY:
			continue

		if str(player.get("role", "")) != role:
			continue

		if not str(player.get("club_id", "")).is_empty():
			continue

		matching_ids.append(player_id)

	if matching_ids.is_empty():
		return ""

	return matching_ids[randi() % matching_ids.size()]

static func _create_fallback_player(players: Dictionary, role: String) -> String:
	var player_id := _make_player_id("free", role, players)
	var gender := _generate_gender()
	players[player_id] = {
		"pseudo": _generate_pseudo(),
		"role": role,
		"gender": gender,
		"portrait": _get_random_portrait_for_gender(gender),
		"club_id": "",
		"level": 1,
		"stats": _generate_base_stats(),
	}
	return player_id

static func _make_player_id(club_id: String, role: String, players: Dictionary) -> String:
	var index := 1
	var player_id := "%s_%s_%02d" % [club_id, role, index]
	while players.has(player_id):
		index += 1
		player_id = "%s_%s_%02d" % [club_id, role, index]
	return player_id

static func _generate_base_stats() -> Dictionary:
	return {
		"mechanics": _generate_stat_grade(),
		"laning": _generate_stat_grade(),
		"vision": _generate_stat_grade(),
		"teamplay": _generate_stat_grade(),
		"mental": _generate_stat_grade(),
	}

static func _generate_stat_grade() -> String:
	return STAT_GRADES[randi() % STAT_GRADES.size()]

static func _generate_unique_pseudo(used_pseudos: Dictionary) -> String:
	var pseudo := _generate_pseudo()
	while used_pseudos.has(pseudo):
		pseudo = _generate_pseudo()

	used_pseudos[pseudo] = true
	return pseudo

static func _generate_pseudo() -> String:
	var prefix: String = PSEUDO_PREFIXES[randi() % PSEUDO_PREFIXES.size()]
	var suffix: String = PSEUDO_SUFFIXES[randi() % PSEUDO_SUFFIXES.size()]
	var number := randi_range(10, 99)
	return "%s%s%d" % [prefix, suffix, number]

static func _generate_gender() -> String:
	return PLAYER_GENDERS[randi() % PLAYER_GENDERS.size()]

static func _get_random_portrait_for_gender(gender: String) -> String:
	var prefix := "homme_"
	if gender == "female":
		prefix = "femme_"

	var portraits := []
	var dir := DirAccess.open(PORTRAITS_DIR)
	if dir == null:
		return ""

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.begins_with(prefix) and file_name.ends_with(".png"):
			portraits.append("%s/%s" % [PORTRAITS_DIR, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()

	if portraits.is_empty():
		return ""

	return portraits[randi() % portraits.size()]

static func _load_json(primary_path: String, debug_copy_path: String) -> Dictionary:
	if FileAccess.file_exists(primary_path):
		return _read_json_file(primary_path)

	return _read_json_file(debug_copy_path)

static func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed

	return {}

static func _save_json(data: Dictionary, primary_path: String, debug_copy_path: String) -> void:
	var text := JSON.stringify(data, "\t")
	var file := FileAccess.open(primary_path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)

	var debug_file := FileAccess.open(debug_copy_path, FileAccess.WRITE)
	if debug_file != null:
		debug_file.store_string(text)
