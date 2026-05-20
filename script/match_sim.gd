extends RefCounted

const ROLES: Array[String] = ["top", "jgl", "mid", "bot", "sup"]
const LANES: Array[String] = ["top", "mid", "bot"]
const GRADE_VALUE: Dictionary = {"E": 35, "D": 50, "C": 65, "B": 78, "A": 88, "S": 97}
const CLASS_COUNTERS: Dictionary = {
	"fighter": "marksman",
	"marksman": "tank",
	"tank": "mage",
	"mage": "fighter",
}

var champions: Dictionary
var items: Dictionary
var game_time := 0.0
var winner := ""
var gold_history: Array[float] = [0.0]
var team_bonus := {
	"player": {"damage": 0.0, "armor": 0.0, "magic_resist": 0.0, "speed": 0.0, "sustain": 0.0, "baron_until": 0.0},
	"ai": {"damage": 0.0, "armor": 0.0, "magic_resist": 0.0, "speed": 0.0, "sustain": 0.0, "baron_until": 0.0},
}
var teams := {"player": {}, "ai": {}}
var towers: Dictionary = {}
var drakes := {"player": 0, "ai": 0}
var event_log: Array[String] = []

var _wave_timer := 0.0
var _jungle_timer := 0.0
var _gank_timer := 18.0
var _duel_timer := 25.0
var _fight_timer := 60.0
var _drake_timer := 300.0
var _nashor_timer := 1200.0
var _push_timer := 35.0

func setup(player_players: Dictionary, ai_players: Dictionary, player_picks: Array[String], ai_picks: Array[String], champions_data: Dictionary, items_data: Dictionary) -> void:
	champions = champions_data
	items = items_data
	teams["player"] = _build_team(player_players, player_picks)
	teams["ai"] = _build_team(ai_players, ai_picks)
	for side in ["player", "ai"]:
		towers[side] = {}
		for lane in LANES:
			towers[side][lane] = 0
	event_log.clear()
	event_log.append("Match started")

func step(delta: float) -> void:
	if not winner.is_empty():
		return

	game_time += delta
	_tick_death_timers(delta)

	_wave_timer += delta
	_jungle_timer += delta
	_gank_timer += delta
	_duel_timer += delta
	_fight_timer += delta
	_drake_timer += delta
	_nashor_timer += delta
	_push_timer += delta

	if _wave_timer >= 20.0:
		_wave_timer -= 20.0
		_resolve_waves()

	if _jungle_timer >= 10.0:
		_jungle_timer -= 10.0
		_resolve_jungle_tick()

	if _gank_timer >= 35.0:
		_gank_timer = randf_range(-8.0, 8.0)
		_resolve_gank()

	if _duel_timer >= 45.0:
		_duel_timer = randf_range(-8.0, 8.0)
		_resolve_lane_duel()

	if game_time >= 1200.0 and _fight_timer >= 55.0:
		_fight_timer = randf_range(-10.0, 10.0)
		_resolve_teamfight()

	if _drake_timer >= 300.0:
		_drake_timer = 0.0
		_resolve_drake()

	if game_time >= 1200.0 and _nashor_timer >= 180.0:
		_nashor_timer = 0.0
		_resolve_nashor()

	if _push_timer >= 30.0:
		_push_timer = 0.0
		_resolve_push()

	_auto_buy_items()
	_update_levels()
	gold_history.append(float(get_gold_diff()))
	if gold_history.size() > 90:
		gold_history.pop_front()

func get_gold_diff() -> int:
	return int(_team_gold("player") - _team_gold("ai"))

func get_snapshot() -> Dictionary:
	return {
		"time": game_time,
		"winner": winner,
		"gold_diff": get_gold_diff(),
		"gold_history": gold_history.duplicate(),
		"teams": teams,
		"towers": towers,
		"drakes": drakes,
		"events": event_log.slice(max(0, event_log.size() - 5), event_log.size()),
	}

func _build_team(players: Dictionary, picks: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	var used_picks: Array[String] = []
	for role in ROLES:
		var player_id: String = _first_player_for_role(players, role)
		var champion_id: String = _first_pick_for_role(picks, role, used_picks)
		if champion_id.is_empty():
			champion_id = _fallback_champion_for_role(role, used_picks)
		used_picks.append(champion_id)

		var player: Dictionary = players.get(player_id, {})
		var champion: Dictionary = champions.get(champion_id, {})
		result[role] = {
			"player_id": player_id,
			"pseudo": str(player.get("pseudo", role.to_upper())),
			"role": role,
			"stats": player.get("stats", {}),
			"champion_id": champion_id,
			"champion": champion,
			"kills": 0,
			"deaths": 0,
			"assists": 0,
			"gold": 500,
			"unspent_gold": 500,
			"level": 1,
			"alive": true,
			"death_timer": 0.0,
			"items": [],
			"cs": 0,
			"power": _base_player_power(player, champion),
		}
	return result

func _first_player_for_role(players: Dictionary, role: String) -> String:
	for player_id in players:
		var player = players[player_id]
		if typeof(player) == TYPE_DICTIONARY and str(player.get("role", "")) == role:
			return str(player_id)
	return ""

func _first_pick_for_role(picks: Array[String], role: String, used: Array[String]) -> String:
	for champion_id in picks:
		var key := str(champion_id)
		if used.has(key):
			continue
		var champion: Dictionary = champions.get(key, {})
		if str(champion.get("role", "")) == role:
			return key
	return ""

func _fallback_champion_for_role(role: String, used: Array[String]) -> String:
	for champion_id in champions:
		var key := str(champion_id)
		var champion: Dictionary = champions[key]
		if str(champion.get("role", "")) == role and not used.has(key):
			return key
	return ""

func _base_player_power(player: Dictionary, champion: Dictionary) -> float:
	var stats: Dictionary = player.get("stats", {})
	var champion_stats: Dictionary = champion.get("base_stats", {})
	var grade_score: float = (
		_grade(stats.get("mechanics", "C")) +
		_grade(stats.get("laning", "C")) +
		_grade(stats.get("vision", "C")) +
		_grade(stats.get("teamplay", "C")) +
		_grade(stats.get("mental", "C"))
	) / 5.0
	return grade_score + float(champion_stats.get("attack_damage", 50)) * 0.25 + float(champion_stats.get("ability_power", 0)) * 0.18

func _resolve_waves() -> void:
	for lane in ["top", "mid", "bot"]:
		for side in ["player", "ai"]:
			var state: Dictionary = teams[side][lane]
			if not bool(state.get("alive", true)):
				continue
			var stats: Dictionary = state.get("stats", {})
			var farm_rate: float = _grade(stats.get("laning", "C")) / 100.0
			var minions: int = int(round(3.0 * farm_rate))
			var gold: int = minions * 35
			state["cs"] = int(state.get("cs", 0)) + minions
			_add_gold(side, lane, gold)
	for side in ["player", "ai"]:
		_add_gold(side, "sup", 55)

func _resolve_jungle_tick() -> void:
	for side in ["player", "ai"]:
		var state: Dictionary = teams[side]["jgl"]
		if not bool(state.get("alive", true)):
			continue
		var stats: Dictionary = state.get("stats", {})
		var clear_score: float = (_grade(stats.get("mechanics", "C")) + _grade(stats.get("mental", "C"))) * 0.5
		var camps: float = clampf(clear_score / 100.0, 0.35, 1.05)
		_add_gold(side, "jgl", int(round(6.0 * 45.0 * camps / 6.0)))

func _resolve_gank() -> void:
	var side := "player"
	if randf() < 0.5:
		side = "ai"
	var enemy: String = _other_side(side)
	var lane: String = _choose_gank_lane(side, enemy)
	var jungler: Dictionary = teams[side]["jgl"]
	var target: Dictionary = teams[enemy][lane]
	if not bool(jungler.get("alive", true)) or not bool(target.get("alive", true)):
		return
	var jungler_stats: Dictionary = jungler.get("stats", {})
	var target_stats: Dictionary = target.get("stats", {})
	var chance: float = 0.32 + (_grade(jungler_stats.get("mechanics", "C")) - _grade(target_stats.get("vision", "C"))) / 220.0
	chance += randf_range(-0.12, 0.12)
	if randf() < clampf(chance, 0.12, 0.72):
		_score_kill(side, "jgl", enemy, lane)
		teams[side][lane]["assists"] = int(teams[side][lane].get("assists", 0)) + 1
		event_log.append("%s gank succeeded on %s" % [side.to_upper(), lane.to_upper()])
	else:
		event_log.append("%s gank failed on %s" % [side.to_upper(), lane.to_upper()])

func _choose_gank_lane(side: String, enemy: String) -> String:
	var weighted: Array[Dictionary] = []
	for lane in ["top", "mid", "bot"]:
		var ally: Dictionary = teams[side][lane]
		var target: Dictionary = teams[enemy][lane]
		var weight: float = 1.0
		weight += maxf(0.0, float(int(target.get("gold", 0)) - int(ally.get("gold", 0))) / 1200.0)
		weight += randf_range(0.0, 1.2)
		var target_stats: Dictionary = target.get("stats", {})
		weight -= _grade(target_stats.get("vision", "C")) / 140.0
		if not bool(target.get("alive", true)):
			weight -= 1.0
		weighted.append({"lane": lane, "weight": maxf(0.1, weight)})
	return _weighted_lane(weighted)

func _resolve_teamfight() -> void:
	var player_power: float = _team_fight_power("player")
	var ai_power: float = _team_fight_power("ai")
	var player_chance: float = clampf(player_power / maxf(1.0, player_power + ai_power), 0.25, 0.75)
	var winner_side: String = "player" if randf() < player_chance else "ai"
	var loser_side: String = _other_side(winner_side)
	event_log.append("%s won a teamfight" % winner_side.to_upper())

	_resolve_fight_deaths(winner_side, false)
	_resolve_fight_deaths(loser_side, true)
	_add_team_gold(winner_side, 850)
	_resolve_push_for_side(winner_side)

func _resolve_lane_duel() -> void:
	var lane: String = LANES[randi() % LANES.size()]
	var player_state: Dictionary = teams["player"][lane]
	var ai_state: Dictionary = teams["ai"][lane]
	if not bool(player_state.get("alive", true)) or not bool(ai_state.get("alive", true)):
		return

	var player_chance: float = _duel_win_chance(player_state, ai_state)
	if randf() > 0.38:
		var pressure_side: String = "player" if randf() < player_chance else "ai"
		_add_gold(pressure_side, lane, 70)
		event_log.append("%s gained lane pressure on %s" % [pressure_side.to_upper(), lane.to_upper()])
		return

	if randf() < player_chance:
		_score_kill("player", lane, "ai", lane)
		event_log.append("PLAYER won a %s duel" % lane.to_upper())
	else:
		_score_kill("ai", lane, "player", lane)
		event_log.append("AI won a %s duel" % lane.to_upper())

func _duel_win_chance(attacker: Dictionary, defender: Dictionary) -> float:
	var attacker_power: float = float(attacker.get("power", 0.0)) + float(attacker.get("gold", 0)) * 0.01 + float(attacker.get("level", 1)) * 6.0
	var defender_power: float = float(defender.get("power", 0.0)) + float(defender.get("gold", 0)) * 0.01 + float(defender.get("level", 1)) * 6.0
	var attacker_champion: Dictionary = attacker.get("champion", {})
	var defender_champion: Dictionary = defender.get("champion", {})
	attacker_power += _class_counter_bonus(str(attacker_champion.get("class", "fighter")), str(defender_champion.get("class", "fighter")))
	defender_power += _class_counter_bonus(str(defender_champion.get("class", "fighter")), str(attacker_champion.get("class", "fighter")))
	attacker_power *= randf_range(0.9, 1.1)
	defender_power *= randf_range(0.9, 1.1)
	return clampf(attacker_power / maxf(1.0, attacker_power + defender_power), 0.25, 0.75)

func _class_counter_bonus(attacker_class: String, defender_class: String) -> float:
	if attacker_class == "support" or defender_class == "support":
		return 0.0
	return 18.0 if str(CLASS_COUNTERS.get(attacker_class, "")) == defender_class else 0.0

func _resolve_fight_deaths(side: String, lost: bool) -> void:
	for role in ROLES:
		var state: Dictionary = teams[side][role]
		if not bool(state.get("alive", true)):
			continue
		var champion: Dictionary = state.get("champion", {})
		var champion_class: String = str(champion.get("class", "fighter"))
		var chance := 0.22 if lost else 0.1
		if champion_class in ["marksman", "mage"]:
			chance += 0.18
		elif champion_class == "tank":
			chance -= 0.08
		if randf() < clampf(chance, 0.04, 0.65):
			_kill_player(side, role)

func _resolve_drake() -> void:
	var side: String = _objective_winner()
	drakes[side] += 1
	var bonus_keys: Array[String] = ["damage", "armor", "magic_resist", "speed", "sustain"]
	var bonus_key: String = bonus_keys[randi() % bonus_keys.size()]
	team_bonus[side][bonus_key] += 0.03
	event_log.append("%s secured drake (+3%% %s)" % [side.to_upper(), bonus_key])

func _resolve_nashor() -> void:
	var side: String = _objective_winner()
	team_bonus[side]["baron_until"] = game_time + 180.0
	event_log.append("%s secured Nashor" % side.to_upper())

func _resolve_push() -> void:
	if game_time < 240.0:
		return
	var diff := get_gold_diff()
	if diff > 700 or _has_nashor("player"):
		_resolve_push_for_side("player")
	elif diff < -700 or _has_nashor("ai"):
		_resolve_push_for_side("ai")

func _resolve_push_for_side(side: String) -> void:
	var enemy: String = _other_side(side)
	var pushes := 1
	if _has_nashor(side) and randf() < 0.4:
		pushes = 2
	for i in range(pushes):
		var best_lane: String = LANES[randi() % LANES.size()]
		for lane in LANES:
			if towers[enemy][lane] < towers[enemy][best_lane]:
				best_lane = lane
		if towers[enemy][best_lane] < 3:
			towers[enemy][best_lane] += 1
			var finisher: String = _best_alive_role(side)
			_add_gold(side, finisher, 300)
			event_log.append("%s destroyed %s T%d" % [side.to_upper(), best_lane.to_upper(), towers[enemy][best_lane]])
		else:
			winner = side
			event_log.append("%s destroyed the Nexus" % side.to_upper())
			return

func _auto_buy_items() -> void:
	for side in ["player", "ai"]:
		for role in ROLES:
			var state: Dictionary = teams[side][role]
			var owned_items: Array = state.get("items", [])
			if owned_items.size() >= 7:
				continue
			var item_id: String = _best_item_for_state(state)
			if item_id.is_empty():
				continue
			var item: Dictionary = items[item_id]
			var cost: int = int(item.get("cost", 99999))
			if int(state.get("unspent_gold", 0)) >= cost:
				state["unspent_gold"] = int(state.get("unspent_gold", 0)) - cost
				owned_items.append(item_id)
				state["items"] = owned_items
				state["power"] = float(state.get("power", 0.0)) + _item_power(item)

func _best_item_for_state(state: Dictionary) -> String:
	var champion: Dictionary = state.get("champion", {})
	var champion_class: String = str(champion.get("class", "fighter"))
	var preferred: Array[String] = []
	if champion_class == "tank":
		preferred = ["titan_heart", "guardian_plate", "spirit_cloak", "swift_boots"]
	elif champion_class == "marksman":
		preferred = ["phantom_bow", "storm_axe", "berserker_boots", "iron_blade"]
	elif champion_class == "mage":
		preferred = ["rift_crown", "void_staff", "ember_orb", "arcane_tome"]
	elif champion_class == "support":
		preferred = ["oracle_charm", "spirit_cloak", "swift_boots", "guardian_plate"]
	else:
		preferred = ["crystal_axe", "shadow_dagger", "storm_axe", "guardian_plate"]
	for item_id in preferred:
		var owned_items: Array = state.get("items", [])
		if items.has(item_id) and not owned_items.has(item_id):
			return item_id
	return ""

func _item_power(item: Dictionary) -> float:
	var stats: Dictionary = item.get("stats", {})
	var power := 0.0
	for key in stats:
		power += float(stats[key]) * 0.08
	return power

func _update_levels() -> void:
	for side in ["player", "ai"]:
		for role in ROLES:
			var state: Dictionary = teams[side][role]
			state["level"] = clampi(1 + int(float(state.get("gold", 0)) / 650.0), 1, 18)

func _tick_death_timers(delta: float) -> void:
	for side in ["player", "ai"]:
		for role in ROLES:
			var state: Dictionary = teams[side][role]
			if bool(state.get("alive", true)):
				continue
			state["death_timer"] = float(state.get("death_timer", 0.0)) - delta
			if float(state.get("death_timer", 0.0)) <= 0.0:
				state["alive"] = true
				state["death_timer"] = 0.0

func _score_kill(killer_side: String, killer_role: String, victim_side: String, victim_role: String) -> void:
	teams[killer_side][killer_role]["kills"] = int(teams[killer_side][killer_role].get("kills", 0)) + 1
	_add_gold(killer_side, killer_role, 300)
	_kill_player(victim_side, victim_role)

func _kill_player(side: String, role: String) -> void:
	var state: Dictionary = teams[side][role]
	state["alive"] = false
	state["deaths"] = int(state.get("deaths", 0)) + 1
	state["death_timer"] = 18.0 + min(42.0, game_time / 60.0 * 1.4)

func _add_gold(side: String, role: String, amount: int) -> void:
	var state: Dictionary = teams[side][role]
	state["gold"] = int(state.get("gold", 0)) + amount
	state["unspent_gold"] = int(state.get("unspent_gold", 0)) + amount

func _add_team_gold(side: String, amount: int) -> void:
	var alive_roles: Array[String] = []
	for role in ROLES:
		if bool(teams[side][role].get("alive", true)):
			alive_roles.append(role)
	if alive_roles.is_empty():
		alive_roles = ROLES.duplicate()
	for role in alive_roles:
		_add_gold(side, role, int(amount / alive_roles.size()))

func _team_gold(side: String) -> int:
	var total: int = 0
	for role in ROLES:
		total += int(teams[side][role].get("gold", 0))
	return total

func _team_fight_power(side: String) -> float:
	var power: float = 0.0
	for role in ROLES:
		var state: Dictionary = teams[side][role]
		if not bool(state.get("alive", true)):
			continue
		power += float(state.get("power", 0.0)) + float(state.get("gold", 0)) * 0.012 + float(state.get("level", 1)) * 8.0
	var bonus: Dictionary = team_bonus[side]
	power *= 1.0 + float(bonus.get("damage", 0.0)) + float(bonus.get("armor", 0.0)) * 0.35 + float(bonus.get("magic_resist", 0.0)) * 0.35 + float(bonus.get("speed", 0.0)) * 0.25 + float(bonus.get("sustain", 0.0)) * 0.4
	return power * randf_range(0.82, 1.18)

func _has_nashor(side: String) -> bool:
	return game_time < float(team_bonus[side].get("baron_until", 0.0))

func _objective_winner() -> String:
	var player_score: float = _team_fight_power("player") + randf_range(-80.0, 80.0)
	var ai_score: float = _team_fight_power("ai") + randf_range(-80.0, 80.0)
	return "player" if player_score >= ai_score else "ai"

func _best_alive_role(side: String) -> String:
	var best_role: String = "top"
	var best_gold: int = -1
	for role in ROLES:
		var state: Dictionary = teams[side][role]
		if bool(state.get("alive", true)) and int(state.get("gold", 0)) > best_gold:
			best_gold = int(state.get("gold", 0))
			best_role = role
	return best_role

func _weighted_lane(weighted: Array) -> String:
	var total: float = 0.0
	for entry in weighted:
		total += float(entry.get("weight", 0.0))
	var roll: float = randf() * total
	for entry in weighted:
		roll -= float(entry.get("weight", 0.0))
		if roll <= 0.0:
			return str(entry.get("lane", "mid"))
	return "mid"

func _other_side(side: String) -> String:
	return "ai" if side == "player" else "player"

func _grade(value: Variant) -> float:
	return float(GRADE_VALUE.get(str(value), 65))
