extends Control

const MAP_TEXTURE_PATH := "res://FONT & sprite/map.png"
const ROLES: Array[String] = ["top", "jgl", "mid", "bot", "sup"]
const LANES: Array[String] = ["top", "mid", "bot"]

var map_texture: Texture2D
var game_time: float = 0.0
var units: Dictionary = {}
var minions: Array[Dictionary] = []
var towers: Dictionary = {}
var recent_events: Array = []
var winner: String = ""
var last_wave_index: int = -1
var active_focus: Dictionary = {}
var focus_until: float = 0.0
var last_focus_signature: String = ""
var last_drake_count: int = 0
var last_nashor_count: int = 0
var next_drake_time: float = 300.0
var next_nashor_time: float = 1200.0
var camp_respawn_until: Dictionary = {}

var map_points: Dictionary = {
	"blue_base": Vector2(0.11, 0.82),
	"red_base": Vector2(0.86, 0.12),
	"blue_nexus": Vector2(0.12, 0.82),
	"red_nexus": Vector2(0.86, 0.12),
	"blue_top_t1": Vector2(0.19, 0.31),
	"blue_top_t2": Vector2(0.25, 0.14),
	"blue_top_t3": Vector2(0.15, 0.50),
	"top_lane_center": Vector2(0.46, 0.10),
	"red_top_t1": Vector2(0.62, 0.12),
	"red_top_t2": Vector2(0.74, 0.10),
	"red_top_t3": Vector2(0.78, 0.20),
	"blue_mid_t1": Vector2(0.50, 0.48),
	"blue_mid_t2": Vector2(0.40, 0.53),
	"blue_mid_t3": Vector2(0.23, 0.72),
	"mid_lane_center": Vector2(0.50, 0.50),
	"red_mid_t1": Vector2(0.61, 0.37),
	"red_mid_t2": Vector2(0.70, 0.25),
	"red_mid_t3": Vector2(0.78, 0.20),
	"blue_bot_t1": Vector2(0.50, 0.87),
	"blue_bot_t2": Vector2(0.23, 0.86),
	"blue_bot_t3": Vector2(0.24, 0.75),
	"bot_lane_center": Vector2(0.63, 0.86),
	"red_bot_t1": Vector2(0.63, 0.84),
	"red_bot_t2": Vector2(0.73, 0.73),
	"red_bot_t3": Vector2(0.86, 0.50),
	"blue_jungle": Vector2(0.31, 0.56),
	"red_jungle": Vector2(0.74, 0.44),
	"river_top": Vector2(0.44, 0.30),
	"river_mid": Vector2(0.52, 0.50),
	"river_bot": Vector2(0.57, 0.69),
	"drake_pit": Vector2(0.53, 0.76),
	"nashor_pit": Vector2(0.47, 0.26),
	"blue_camp_1": Vector2(0.34, 0.41),
	"blue_camp_2": Vector2(0.25, 0.45),
	"blue_camp_3": Vector2(0.30, 0.51),
	"blue_camp_4": Vector2(0.25, 0.57),
	"blue_camp_5": Vector2(0.39, 0.69),
	"blue_camp_6": Vector2(0.42, 0.78),
	"red_camp_1": Vector2(0.67, 0.31),
	"red_camp_2": Vector2(0.75, 0.37),
	"red_camp_3": Vector2(0.70, 0.44),
	"red_camp_4": Vector2(0.77, 0.50),
	"red_camp_5": Vector2(0.68, 0.58),
	"red_camp_6": Vector2(0.81, 0.66),
}

func _ready() -> void:
	map_texture = load(MAP_TEXTURE_PATH)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_from_snapshot(snapshot: Dictionary, delta: float) -> void:
	game_time = float(snapshot.get("time", 0.0))
	winner = str(snapshot.get("winner", ""))
	_sync_points_from_nodes()
	towers = snapshot.get("towers", {})
	recent_events = snapshot.get("events", [])
	_update_objective_timers(snapshot)
	var teams: Dictionary = snapshot.get("teams", {})
	_update_focus_from_events()
	_ensure_units(teams)
	_spawn_minion_waves()
	_update_unit_targets(teams, delta)
	_update_minions(teams, delta)
	queue_redraw()

func _update_objective_timers(snapshot: Dictionary) -> void:
	var drakes: Dictionary = snapshot.get("drakes", {})
	var nashors: Dictionary = snapshot.get("nashors", {})
	var current_drakes: int = int(drakes.get("player", 0)) + int(drakes.get("ai", 0))
	var current_nashors: int = int(nashors.get("player", 0)) + int(nashors.get("ai", 0))
	if current_drakes > last_drake_count:
		next_drake_time = game_time + 300.0
	last_drake_count = current_drakes
	if current_nashors > last_nashor_count:
		next_nashor_time = game_time + 180.0
	last_nashor_count = current_nashors

func _sync_points_from_nodes() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or not has_node("point_nodes"):
		return
	var point_nodes: Node = get_node("point_nodes")
	for child in point_nodes.get_children():
		if child is Control:
			var control: Control = child as Control
			var point_name: String = control.name.replace("_marker", "")
			var center: Vector2 = control.position + control.size * 0.5
			map_points[point_name] = Vector2(center.x / size.x, center.y / size.y)
			control.visible = false
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ensure_units(teams: Dictionary) -> void:
	for side in ["player", "ai"]:
		if not teams.has(side):
			continue
		for role in ROLES:
			var key: String = "%s_%s" % [side, role]
			if units.has(key):
				continue
			var start_point: String = "blue_base" if side == "player" else "red_base"
			units[key] = {
				"side": side,
				"role": role,
				"pos": map_points[start_point],
				"route": [],
				"route_index": 0,
				"target_signature": "",
				"hp": 1.0,
				"state": "farming",
				"recall_timer": 0.0,
				"recalling": false,
				"camp_index": 1,
				"clear_timer": 0.0,
				"decision_tick": -1,
				"lane_target_key": "",
			}

func _spawn_minion_waves() -> void:
	var wave_index: int = int(game_time / 20.0)
	if wave_index <= last_wave_index:
		return
	last_wave_index = wave_index
	for lane in LANES:
		for side in ["player", "ai"]:
			var route: Array[Vector2] = _minion_route(side, lane)
			for i in range(3):
				var lane_offset: Vector2 = _minion_spacing(i, side, lane)
				minions.append({
					"side": side,
					"lane": lane,
					"pos": route[0] + lane_offset,
					"route": route,
					"route_index": 1,
					"offset": lane_offset,
					"hp": 1.0,
					"attack_timer": 0.0,
				})

func _update_unit_targets(teams: Dictionary, delta: float) -> void:
	for side in ["player", "ai"]:
		if not teams.has(side):
			continue
		for role in ROLES:
			var key: String = "%s_%s" % [side, role]
			var visual: Dictionary = units[key]
			var state: Dictionary = teams[side][role]
			var alive: bool = bool(state.get("alive", true))
			if not alive:
				visual["state"] = "dead"
				visual["target_signature"] = "dead"
				visual["route"] = []
				visual["hp"] = 0.0
				visual["pos"] = map_points["blue_base" if side == "player" else "red_base"]
				units[key] = visual
				continue

			var target_key: String = _default_target_key(side, role)
			if role == "jgl":
				target_key = _jungle_target_key(visual, side, delta)
			else:
				target_key = _laner_target_key(visual, side, role, state, teams)
			var target_state: String = _default_state(role)
			var base_key: String = "blue_base" if side == "player" else "red_base"
			if _focus_is_active() and _role_joins_focus(role, active_focus):
				target_key = str(active_focus.get("point", target_key))
				target_state = str(active_focus.get("state", "fighting"))
				visual["recalling"] = false
				visual["recall_timer"] = 0.0
				visual["hp"] = maxf(0.16, float(visual.get("hp", 1.0)) - delta * randf_range(0.035, 0.09))
			else:
				var visual_pos: Vector2 = visual["pos"]
				if _is_at_point(visual_pos, base_key):
					visual["hp"] = minf(1.0, float(visual.get("hp", 1.0)) + delta * 0.22)
				_update_recall_state(visual, side, role, delta)
				if bool(visual.get("recalling", false)):
					target_state = "recalling"
					target_key = str(visual.get("target_key", target_key))
				elif str(visual.get("state", "")) == "retreating":
					target_state = "retreating"
					target_key = str(visual.get("target_key", target_key))
				elif float(visual.get("hp", 1.0)) < 0.36:
					target_state = "playing safe"
					target_key = _safe_point_key(side, role)
				elif role != "jgl":
					target_state = _lane_state_for_target(side, role, target_key)
			visual["state"] = target_state
			if bool(visual.get("recalling", false)):
				units[key] = visual
				continue

			var spaced_target: Vector2 = map_points[target_key] + _unit_spacing(side, role, target_key)
			var signature: String = "%s:%s:%s" % [target_key, side, role]
			if str(visual.get("target_signature", "")) != signature:
				var current_pos: Vector2 = visual["pos"]
				visual["route"] = _build_route(current_pos, side, role, target_key, spaced_target)
				visual["route_index"] = 0
				visual["target_signature"] = signature

			visual["pos"] = _advance_route(visual, delta)
			units[key] = visual

func _advance_route(visual: Dictionary, delta: float) -> Vector2:
	var pos: Vector2 = visual["pos"]
	var route: Array = visual.get("route", [])
	if route.is_empty():
		return pos
	var index: int = int(visual.get("route_index", 0))
	index = clampi(index, 0, route.size() - 1)
	var target: Vector2 = route[index]
	var speed: float = 0.18
	if str(visual.get("state", "")) in ["fighting", "objective"]:
		speed = 0.24
	pos = pos.move_toward(target, delta * speed)
	if pos.distance_to(target) < 0.008 and index < route.size() - 1:
		visual["route_index"] = index + 1
	return pos

func _update_recall_state(visual: Dictionary, side: String, role: String, delta: float) -> void:
	var hp: float = float(visual.get("hp", 1.0))
	var pos: Vector2 = visual["pos"]
	var base_key: String = "blue_base" if side == "player" else "red_base"
	if _is_at_point(pos, base_key):
		visual["recalling"] = false
		visual["recall_timer"] = 0.0
		return
	if bool(visual.get("recalling", false)):
		if _enemy_near(pos, side, 0.075):
			visual["recalling"] = false
			visual["recall_timer"] = 0.0
			visual["state"] = "retreating"
			visual["target_key"] = "blue_jungle" if side == "player" else "red_jungle"
			visual["target_signature"] = ""
			return
		visual["recall_timer"] = float(visual.get("recall_timer", 0.0)) + delta
		if float(visual.get("recall_timer", 0.0)) >= 4.0:
			visual["recalling"] = false
			visual["recall_timer"] = 0.0
			visual["pos"] = map_points[base_key]
			visual["route"] = []
			visual["route_index"] = 0
			visual["target_signature"] = ""
			visual["hp"] = 1.0
		return
	if str(visual.get("state", "")) == "retreating":
		var safe_key: String = str(visual.get("target_key", "blue_jungle" if side == "player" else "red_jungle"))
		if _is_at_point(pos, safe_key):
			visual["state"] = _default_state(role)
			visual["target_key"] = _default_target_key(side, role)
			visual["target_signature"] = ""
		return
	if hp < 0.42 and not _enemy_near(pos, side, 0.095) and randf() < delta * 0.22:
		visual["recalling"] = true
		visual["recall_timer"] = 0.0
		visual["target_key"] = _default_target_key(side, role)

func _laner_target_key(visual: Dictionary, side: String, role: String, state: Dictionary, teams: Dictionary) -> String:
	var hp: float = float(visual.get("hp", 1.0))
	if hp < 0.34:
		return _safe_point_key(side, role)
	var enemy_side: String = "ai" if side == "player" else "player"
	var compare_role: String = "bot" if role == "sup" else role
	var gold_diff: int = int(state.get("gold", 0))
	var enemy_hp: float = 1.0
	if teams.has(enemy_side) and teams[enemy_side].has(compare_role):
		var enemy_state: Dictionary = teams[enemy_side][compare_role]
		gold_diff -= int(enemy_state.get("gold", 0))
		var enemy_key: String = "%s_%s" % [enemy_side, compare_role]
		if units.has(enemy_key):
			enemy_hp = float(units[enemy_key].get("hp", 1.0))
	var decision_tick: int = int(game_time / 9.0)
	if int(visual.get("decision_tick", -1)) == decision_tick and str(visual.get("lane_target_key", "")).length() > 0:
		return str(visual.get("lane_target_key", ""))
	visual["decision_tick"] = decision_tick
	var target_key: String = _default_target_key(side, role)
	if hp < 0.48 or gold_diff < -450:
		target_key = _safe_point_key(side, role)
	elif gold_diff > 450 or hp > enemy_hp + 0.18:
		target_key = _pressure_point_key(side, role)
	elif decision_tick % 3 == 0:
		target_key = _lane_hold_point_key(side, role)
	visual["lane_target_key"] = target_key
	return target_key

func _jungle_target_key(visual: Dictionary, side: String, delta: float) -> String:
	var prefix: String = "blue" if side == "player" else "red"
	var camp_index: int = int(visual.get("camp_index", 1))
	var camp_key: String = "%s_camp_%d" % [prefix, camp_index]
	var guard: int = 0
	while not _camp_available(camp_key) and guard < 6:
		camp_index += 1
		if camp_index > 6:
			camp_index = 1
		camp_key = "%s_camp_%d" % [prefix, camp_index]
		guard += 1
	if not _camp_available(camp_key):
		visual["clear_timer"] = 0.0
		return "%s_jungle" % prefix
	visual["camp_index"] = camp_index
	var visual_pos: Vector2 = visual["pos"]
	if _is_at_point(visual_pos, camp_key, 0.022):
		visual["clear_timer"] = float(visual.get("clear_timer", 0.0)) + delta
		if float(visual.get("clear_timer", 0.0)) >= 2.0:
			camp_respawn_until[camp_key] = game_time + 70.0
			camp_index += 1
			if camp_index > 6:
				camp_index = 1
			visual["camp_index"] = camp_index
			visual["clear_timer"] = 0.0
			visual["target_signature"] = ""
			camp_key = "%s_camp_%d" % [prefix, camp_index]
	else:
		visual["clear_timer"] = 0.0
	return camp_key

func _camp_available(camp_key: String) -> bool:
	return game_time >= float(camp_respawn_until.get(camp_key, 0.0))

func _update_minions(teams: Dictionary, delta: float) -> void:
	for i in range(minions.size() - 1, -1, -1):
		var minion: Dictionary = minions[i]
		var pos: Vector2 = minion["pos"]
		var lane: String = str(minion.get("lane", "mid"))
		var side: String = str(minion.get("side", "player"))
		var enemy_side: String = "ai" if side == "player" else "player"
		var enemy_pos: Vector2 = _lane_enemy_position(teams, enemy_side, lane)
		if enemy_pos != Vector2.ZERO and pos.distance_to(enemy_pos) < 0.055:
			minion["hp"] = float(minion.get("hp", 1.0)) - delta * 0.55
			pos = pos.move_toward(enemy_pos, delta * 0.05)
			if float(minion.get("hp", 1.0)) <= 0.0:
				minions.remove_at(i)
				continue
		else:
			pos = _advance_minion_route(minion, delta)
		if float(minion.get("hp", 1.0)) <= 0.0:
			minions.remove_at(i)
			continue
		minion["pos"] = pos
		minions[i] = minion

func _advance_minion_route(minion: Dictionary, delta: float) -> Vector2:
	var pos: Vector2 = minion["pos"]
	var route: Array = minion.get("route", [])
	var index: int = int(minion.get("route_index", 1))
	if route.is_empty() or index >= route.size():
		minion["hp"] = float(minion.get("hp", 1.0)) - delta * 0.12
		return pos
	var route_target: Vector2 = route[index]
	var route_offset: Vector2 = minion.get("offset", Vector2.ZERO)
	var target: Vector2 = route_target + route_offset
	pos = pos.move_toward(target, delta * 0.105)
	if pos.distance_to(target) < 0.01:
		index += 1
		minion["route_index"] = index
		if index >= route.size():
			minion["attack_timer"] = float(minion.get("attack_timer", 0.0)) + delta
			minion["hp"] = float(minion.get("hp", 1.0)) - delta * 0.08
	return pos

func _update_focus_from_events() -> void:
	var detected: Dictionary = {}
	var signature: String = ""
	for event in recent_events:
		var text: String = str(event).to_lower()
		if text.find("nashor") != -1:
			detected = {"point": "nashor_pit", "state": "objective", "scope": "team"}
		elif text.find("drake") != -1:
			detected = {"point": "drake_pit", "state": "objective", "scope": "team"}
		elif text.find("teamfight") != -1:
			detected = {"point": "river_mid", "state": "fighting", "scope": "team"}
		elif text.find("bot") != -1:
			detected = {"point": "bot_lane_center", "state": "fighting", "scope": "bot"}
		elif text.find("top") != -1:
			detected = {"point": "top_lane_center", "state": "fighting", "scope": "top"}
		elif text.find("mid") != -1:
			detected = {"point": "mid_lane_center", "state": "fighting", "scope": "mid"}
		if not detected.is_empty():
			signature = "%s:%s" % [str(detected.get("point", "")), text]
			break
	if not detected.is_empty() and signature != last_focus_signature:
		active_focus = detected
		last_focus_signature = signature
		focus_until = game_time + 7.5

func _focus_is_active() -> bool:
	return not active_focus.is_empty() and game_time <= focus_until

func _role_joins_focus(role: String, focus: Dictionary) -> bool:
	var scope: String = str(focus.get("scope", "team"))
	if scope == "team":
		return true
	if scope == "bot":
		return role in ["bot", "sup", "jgl"]
	if scope == "mid":
		return role in ["mid", "jgl", "sup"]
	if scope == "top":
		return role in ["top", "jgl"]
	return false

func _default_target_key(side: String, role: String) -> String:
	if role == "top":
		return "top_lane_center"
	if role == "mid":
		return "mid_lane_center"
	if role == "bot" or role == "sup":
		return "bot_lane_center"
	return "blue_jungle" if side == "player" else "red_jungle"

func _safe_point_key(side: String, role: String) -> String:
	if role != "jgl":
		return _first_alive_tower_key(side, _lane_for_role(role))
	return "blue_jungle" if side == "player" else "red_jungle"

func _lane_hold_point_key(side: String, role: String) -> String:
	if role != "jgl":
		return _first_alive_tower_key(side, _lane_for_role(role))
	return "blue_jungle" if side == "player" else "red_jungle"

func _pressure_point_key(side: String, role: String) -> String:
	var lane: String = _lane_for_role(role)
	var enemy_side: String = "ai" if side == "player" else "player"
	return _first_alive_tower_key(enemy_side, lane)

func _first_alive_tower_key(team_side: String, lane: String) -> String:
	var prefix: String = "blue" if team_side == "player" else "red"
	var destroyed_count: int = _destroyed_tower_count(team_side, lane)
	if destroyed_count >= 3:
		return "%s_nexus" % prefix
	return "%s_%s_t%d" % [prefix, lane, destroyed_count + 1]

func _destroyed_tower_count(team_side: String, lane: String) -> int:
	if towers.has(team_side) and towers[team_side].has(lane):
		return clampi(int(towers[team_side][lane]), 0, 3)
	return 0

func _lane_for_role(role: String) -> String:
	if role == "top":
		return "top"
	if role == "mid":
		return "mid"
	return "bot"

func _lane_state_for_target(side: String, role: String, target_key: String) -> String:
	if target_key == _lane_hold_point_key(side, role):
		return "holding wave"
	if target_key == _safe_point_key(side, role):
		return "playing safe"
	if target_key.find("_t") != -1:
		return "pressuring"
	return _default_state(role)

func _default_state(role: String) -> String:
	if role == "jgl":
		return "farming jungle"
	if role == "sup":
		return "roaming"
	return "farming"

func _build_route(current_pos: Vector2, side: String, role: String, target_key: String, final_target: Vector2) -> Array[Vector2]:
	var route: Array[Vector2] = [current_pos]
	if target_key == "drake_pit":
		if role == "bot" or role == "sup":
			route.append(map_points["river_bot"])
		elif role == "mid":
			route.append(map_points["river_mid"])
		elif role == "top":
			route.append(map_points["river_mid"])
		else:
			route.append(map_points["blue_jungle" if side == "player" else "red_jungle"])
			route.append(map_points["river_bot"])
	elif target_key == "nashor_pit":
		if role == "top":
			route.append(map_points["river_top"])
		elif role == "mid":
			route.append(map_points["river_mid"])
		elif role == "bot" or role == "sup":
			route.append(map_points["river_mid"])
		else:
			route.append(map_points["blue_jungle" if side == "player" else "red_jungle"])
			route.append(map_points["river_top"])
	elif target_key.ends_with("_lane_center"):
		route.append(_lane_approach_point(side, target_key))
	elif target_key.find("_t") != -1:
		var lane: String = _lane_from_point_key(target_key)
		route.append(_lane_approach_point(side, "%s_lane_center" % lane))
	elif target_key.find("_camp_") != -1:
		route.append(map_points["blue_jungle" if side == "player" else "red_jungle"])
	elif target_key in ["blue_jungle", "red_jungle"]:
		route.append(map_points["blue_base" if side == "player" else "red_base"])
	else:
		route.append(map_points["river_mid"])
	route.append(final_target)
	return route

func _lane_from_point_key(point_key: String) -> String:
	if point_key.find("_top_") != -1:
		return "top"
	if point_key.find("_mid_") != -1:
		return "mid"
	return "bot"

func _lane_approach_point(side: String, target_key: String) -> Vector2:
	if target_key == "top_lane_center":
		return map_points[_first_alive_tower_key(side, "top")]
	if target_key == "mid_lane_center":
		return map_points[_first_alive_tower_key(side, "mid")]
	return map_points[_first_alive_tower_key(side, "bot")]

func _unit_spacing(side: String, role: String, target_key: String) -> Vector2:
	var index: int = ROLES.find(role)
	var side_shift: int = -1 if side == "player" else 1
	var angle: float = float(index) / float(ROLES.size()) * TAU
	var radius: float = 0.032
	if target_key.ends_with("_lane_center"):
		radius = 0.018
	if target_key.find("_camp_") != -1:
		radius = 0.01
	return Vector2(cos(angle), sin(angle)) * radius + Vector2(float(side_shift) * 0.012, 0.0)

func _minion_route(side: String, lane: String) -> Array[Vector2]:
	var prefix: String = "blue" if side == "player" else "red"
	var enemy_prefix: String = "red" if side == "player" else "blue"
	return [
		map_points["%s_base" % prefix],
		map_points["%s_%s_t3" % [prefix, lane]],
		map_points["%s_%s_t2" % [prefix, lane]],
		map_points["%s_%s_t1" % [prefix, lane]],
		map_points["%s_lane_center" % lane],
		map_points["%s_%s_t1" % [enemy_prefix, lane]],
		map_points["%s_%s_t2" % [enemy_prefix, lane]],
		map_points["%s_%s_t3" % [enemy_prefix, lane]],
		map_points["%s_base" % enemy_prefix],
	]

func _minion_spacing(index: int, side: String, lane: String) -> Vector2:
	var direction: float = 1.0 if side == "player" else -1.0
	var lane_shift: Vector2 = Vector2(0.0, 0.0)
	if lane == "top":
		lane_shift = Vector2(0.004, -0.006)
	elif lane == "bot":
		lane_shift = Vector2(-0.004, 0.006)
	return Vector2(float(index) * -0.012 * direction, float(index - 1) * 0.007) + lane_shift

func _lane_enemy_position(teams: Dictionary, enemy_side: String, lane: String) -> Vector2:
	if not teams.has(enemy_side):
		return Vector2.ZERO
	var roles: Array[String] = [lane]
	if lane == "bot":
		roles.append("sup")
	for role in roles:
		if teams[enemy_side].has(role) and bool(teams[enemy_side][role].get("alive", true)):
			var unit_key: String = "%s_%s" % [enemy_side, role]
			if units.has(unit_key):
				return units[unit_key].get("pos", Vector2.ZERO)
	return Vector2.ZERO

func _enemy_near(pos: Vector2, side: String, distance: float) -> bool:
	for key in units:
		var unit: Dictionary = units[key]
		if str(unit.get("side", "")) == side:
			continue
		if float(unit.get("hp", 1.0)) <= 0.01:
			continue
		var enemy_pos: Vector2 = unit.get("pos", Vector2.ZERO)
		if pos.distance_to(enemy_pos) <= distance:
			return true
	return false

func _is_at_point(pos: Vector2, point_key: String, distance: float = 0.045) -> bool:
	if not map_points.has(point_key):
		return false
	return pos.distance_to(map_points[point_key]) <= distance

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.78, 0.35, 0.9), false, 3.0)
	_draw_jungle_camps_and_nexus()
	_draw_objectives()
	_draw_towers()
	_draw_minions()
	_draw_units()

func _draw_objectives() -> void:
	if _drake_visible():
		_draw_point("drake_pit", Color(0.08, 0.95, 0.35), 14.0)
	if _nashor_visible():
		_draw_point("nashor_pit", Color(0.58, 0.18, 0.95), 18.0)

func _draw_towers() -> void:
	for side in ["player", "ai"]:
		for lane in LANES:
			var destroyed_count: int = _destroyed_tower_count(side, lane)
			for tier in range(1, 4):
				var point_key: String = _tower_key(side, lane, tier)
				var alive: bool = destroyed_count < tier
				var color: Color = Color(0.1, 0.55, 1.0) if side == "player" else Color(1.0, 0.18, 0.18)
				var p: Vector2 = _to_screen(map_points[point_key])
				var tower_rect: Rect2 = Rect2(p - Vector2(8, 8), Vector2(16, 16))
				if alive:
					draw_rect(tower_rect, color, true)
					draw_rect(tower_rect, Color.BLACK, false, 2.0)
				else:
					draw_line(p + Vector2(-9, -9), p + Vector2(9, 9), Color(1.0, 0.08, 0.08), 3.0)
					draw_line(p + Vector2(-9, 9), p + Vector2(9, -9), Color(1.0, 0.08, 0.08), 3.0)

func _draw_minions() -> void:
	for minion in minions:
		var minion_pos: Vector2 = minion["pos"]
		var pos: Vector2 = _to_screen(minion_pos)
		var alpha: float = clampf(float(minion.get("hp", 1.0)), 0.18, 0.92)
		draw_circle(pos, 3.6, Color(0.02, 0.02, 0.02, alpha))

func _draw_units() -> void:
	for key in units:
		var unit: Dictionary = units[key]
		var pos: Vector2 = _to_screen(unit["pos"])
		var side: String = str(unit.get("side", "player"))
		var hp: float = float(unit.get("hp", 1.0))
		var alive: bool = hp > 0.01
		var color: Color = Color(0.1, 0.55, 1.0) if side == "player" else Color(1.0, 0.18, 0.18)
		if not alive:
			color = Color(0.4, 0.4, 0.4, 0.65)
		var radius: float = 12.0 if alive else 9.0
		if bool(unit.get("recalling", false)):
			var aura_color: Color = Color(0.1, 0.55, 1.0, 0.24) if side == "player" else Color(1.0, 0.18, 0.18, 0.24)
			draw_circle(pos, radius + 13.0 + sin(game_time * 8.0) * 2.0, aura_color)
			draw_circle(pos, radius + 13.0, Color(1, 1, 1, 0.22), false, 2.0)
		if str(unit.get("state", "")) in ["fighting", "objective"]:
			draw_circle(pos, radius + 6.0, Color(1.0, 0.9, 0.25, 0.26))
		draw_circle(pos, radius, color)
		draw_circle(pos, radius, Color.BLACK, false, 2.0)
		_draw_health_bar(pos + Vector2(-16, -23), hp)
		_draw_role_text(pos + Vector2(-12, 4), str(unit.get("role", "")).to_upper())

func _draw_health_bar(pos: Vector2, hp: float) -> void:
	draw_rect(Rect2(pos, Vector2(32, 5)), Color(0.08, 0.08, 0.08, 0.9), true)
	var fill_color: Color = Color(0.1, 0.9, 0.28) if hp > 0.35 else Color(1.0, 0.18, 0.18)
	draw_rect(Rect2(pos, Vector2(32.0 * clampf(hp, 0.0, 1.0), 5)), fill_color, true)

func _draw_jungle_camps_and_nexus() -> void:
	_draw_nexus("player", "blue_nexus", Color(0.1, 0.55, 1.0, 0.88))
	_draw_nexus("ai", "red_nexus", Color(1.0, 0.18, 0.18, 0.88))
	for i in range(1, 7):
		var blue_key: String = "blue_camp_%d" % i
		var red_key: String = "red_camp_%d" % i
		if _camp_available(blue_key):
			_draw_point(blue_key, Color(0.18, 0.9, 0.45, 0.42), 6.0)
		if _camp_available(red_key):
			_draw_point(red_key, Color(0.18, 0.9, 0.45, 0.42), 6.0)

func _draw_nexus(side: String, point_key: String, color: Color) -> void:
	var p: Vector2 = _to_screen(map_points[point_key])
	var destroyed: bool = winner == ("ai" if side == "player" else "player")
	if not destroyed:
		draw_circle(p, 17.0, color)
		draw_circle(p, 17.0, Color.BLACK, false, 2.0)
	else:
		draw_line(p + Vector2(-14, -14), p + Vector2(14, 14), Color(1.0, 0.08, 0.08), 4.0)
		draw_line(p + Vector2(-14, 14), p + Vector2(14, -14), Color(1.0, 0.08, 0.08), 4.0)

func _draw_role_text(pos: Vector2, text: String) -> void:
	var font: Font = get_theme_default_font()
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

func _draw_point(point_key: String, color: Color, radius: float) -> void:
	var p: Vector2 = _to_screen(map_points[point_key])
	draw_circle(p, radius, color)
	draw_circle(p, radius, Color.BLACK, false, 2.0)

func _tower_key(side: String, lane: String, tier: int) -> String:
	var prefix: String = "blue" if side == "player" else "red"
	return "%s_%s_t%d" % [prefix, lane, tier]

func _drake_visible() -> bool:
	return game_time >= next_drake_time

func _nashor_visible() -> bool:
	if game_time < 1200.0:
		return false
	return game_time >= next_nashor_time

func _to_screen(normalized: Vector2) -> Vector2:
	return Vector2(normalized.x * size.x, normalized.y * size.y)
