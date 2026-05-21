extends RefCounted

const ROLES: Array[String] = ["top", "jgl", "mid", "bot", "sup"]
const LANES: Array[String] = ["top", "mid", "bot"]
const GRADE_VALUE: Dictionary = {"E": 35, "D": 50, "C": 65, "B": 78, "A": 88, "S": 97}
const ASSIST_GOLD := 75
const SUPPORT_PASSIVE_GOLD := 45
const DRAKE_INTERVAL := 300.0
const MID_GAME_START := 900.0
const NASHOR_SPAWN := 1200.0
const LATE_GAME_START := 1500.0
const JUNGLE_TICK_INTERVAL := 14.0
const KILL_XP := 260
const ASSIST_XP := 120
const MINION_XP := 48
const JUNGLE_CS_XP := 54
const DRAKE_TEAM_XP := 170
const NASHOR_TEAM_XP := 320
const TOWER_TEAM_XP := 150
const TIME_XP_LANER := 24
const TIME_XP_JGL := 20
const TIME_XP_SUP := 30
const LEVEL_XP: Array[int] = [0, 280, 660, 1140, 1720, 2400, 3180, 4060, 5040, 6120, 7300, 8580, 9960, 11440, 13020, 14700, 16480, 18360]
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
var nashors := {"player": 0, "ai": 0}
var event_log: Array[String] = []

var _wave_timer := 0.0
var _jungle_timer := 0.0
var _gank_timer := 18.0
var _duel_timer := 25.0
var _fight_timer := 60.0
var _drake_timer := 0.0
var _nashor_timer := 1200.0
var _push_timer := 35.0
var _support_roam_timer := 0.0
var _lane_fight_heat := {"top": 0.0, "mid": 0.0, "bot": 0.0}

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
	_tick_lane_fight_heat(delta)

	_wave_timer += delta
	_jungle_timer += delta
	_gank_timer += delta
	_duel_timer += delta
	_fight_timer += delta
	_drake_timer += delta
	_nashor_timer += delta
	_push_timer += delta
	_support_roam_timer += delta

	if _wave_timer >= 20.0:
		_wave_timer -= 20.0
		_resolve_waves()

	if _jungle_timer >= JUNGLE_TICK_INTERVAL:
		_jungle_timer -= JUNGLE_TICK_INTERVAL
		_resolve_jungle_tick()

	if _gank_timer >= _gank_interval():
		_gank_timer = randf_range(-10.0, 8.0)
		_resolve_gank()

	if _support_roam_timer >= 28.0:
		_support_roam_timer = randf_range(-6.0, 6.0)
		_resolve_support_roams()

	if _duel_timer >= _duel_interval():
		_duel_timer = randf_range(-8.0, 8.0)
		_resolve_lane_duel()

	if game_time >= MID_GAME_START and _fight_timer >= _teamfight_interval():
		_fight_timer = randf_range(-10.0, 10.0)
		_resolve_teamfight()

	if _drake_timer >= DRAKE_INTERVAL:
		_drake_timer = 0.0
		_resolve_drake()

	if game_time >= NASHOR_SPAWN and _nashor_timer >= 180.0:
		_nashor_timer = 0.0
		_resolve_nashor()

	if _push_timer >= 30.0:
		_push_timer = 0.0
		_resolve_push()

	_auto_buy_items()
	_update_levels()
	gold_history.append(float(get_gold_diff()))

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
		"nashors": nashors,
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
			"xp": 0,
			"level": 1,
			"alive": true,
			"death_timer": 0.0,
			"vision_control": 0.0,
			"last_support_action": "lane",
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
			_add_xp(side, lane, minions * MINION_XP)
	for side in ["player", "ai"]:
		for role in ROLES:
			if not bool(teams[side][role].get("alive", true)):
				continue
			if role == "jgl":
				_add_xp(side, role, TIME_XP_JGL)
			elif role == "sup":
				_add_xp(side, role, TIME_XP_SUP)
			else:
				_add_xp(side, role, TIME_XP_LANER)
	for side in ["player", "ai"]:
		if bool(teams[side]["sup"].get("alive", true)):
			_add_gold(side, "sup", SUPPORT_PASSIVE_GOLD)

func _resolve_jungle_tick() -> void:
	for side in ["player", "ai"]:
		var state: Dictionary = teams[side]["jgl"]
		if not bool(state.get("alive", true)):
			continue
		var stats: Dictionary = state.get("stats", {})
		var clear_score: float = (_grade(stats.get("mechanics", "C")) + _grade(stats.get("mental", "C"))) * 0.5
		var camps: float = clampf(clear_score / 100.0, 0.35, 1.05)
		var objective_soon: bool = (DRAKE_INTERVAL - _drake_timer) <= 45.0 or (game_time >= NASHOR_SPAWN and _nashor_timer >= 135.0)
		var activity_roll := randf()
		var tempo_factor := 1.0
		if objective_soon:
			tempo_factor -= 0.25
		if activity_roll < 0.28:
			tempo_factor -= 0.45
		elif activity_roll < 0.48:
			tempo_factor -= 0.25
		tempo_factor = clampf(tempo_factor, 0.25, 1.0)
		var cs_gain: int = clampi(int(round(2.2 * camps * tempo_factor)), 0, 3)
		state["cs"] = int(state.get("cs", 0)) + cs_gain
		_add_gold(side, "jgl", int(round(34.0 * camps * tempo_factor)))
		_add_xp(side, "jgl", int(round(float(cs_gain) * JUNGLE_CS_XP + 18.0 * tempo_factor)))

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
	_register_lane_fight(lane, false)
	var jungler_stats: Dictionary = jungler.get("stats", {})
	var target_stats: Dictionary = target.get("stats", {})
	var chance: float = 0.24 + (_grade(jungler_stats.get("mechanics", "C")) - _grade(target_stats.get("vision", "C"))) / 260.0
	var support_roam: bool = _support_is_helping_gank(side, lane)
	if support_roam:
		var support_stats: Dictionary = teams[side]["sup"].get("stats", {})
		chance += (_grade(support_stats.get("teamplay", "C")) + _grade(support_stats.get("vision", "C"))) / 560.0
	if game_time < MID_GAME_START:
		chance -= 0.04
	chance *= _lane_kill_multiplier(lane)
	chance += randf_range(-0.10, 0.10)
	if randf() < clampf(chance, 0.08, 0.58):
		var assists: Array[String] = [lane]
		if support_roam:
			assists.append("sup")
		_score_kill(side, "jgl", enemy, lane, assists)
		_register_lane_fight(lane, true)
		event_log.append("%s gank succeeded on %s" % [side.to_upper(), lane.to_upper()])
	else:
		if support_roam:
			_apply_failed_support_roam(side)
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
	var player_chance: float = _fight_win_chance(player_power, ai_power)
	var winner_side: String = "player" if randf() < player_chance else "ai"
	var loser_side: String = _other_side(winner_side)
	event_log.append("%s won a teamfight" % winner_side.to_upper())

	_resolve_fight_deaths(winner_side, false)
	_resolve_fight_deaths(loser_side, true)
	_add_team_gold(winner_side, 850)
	_resolve_push_for_side(winner_side, true)

func _resolve_support_roams() -> void:
	for side in ["player", "ai"]:
		var support: Dictionary = teams[side]["sup"]
		var adc: Dictionary = teams[side]["bot"]
		var jungler: Dictionary = teams[side]["jgl"]
		if not bool(support.get("alive", true)):
			continue

		var stats: Dictionary = support.get("stats", {})
		var vision: float = _grade(stats.get("vision", "C"))
		var teamplay: float = _grade(stats.get("teamplay", "C"))
		var mental: float = _grade(stats.get("mental", "C"))
		var enemy: String = _other_side(side)
		var enemy_bot: Dictionary = teams[enemy]["bot"]
		var adc_safe: bool = bool(adc.get("alive", true)) and (not bool(enemy_bot.get("alive", true)) or int(adc.get("gold", 0)) + 350 >= int(enemy_bot.get("gold", 0)))
		var objective_soon: bool = (DRAKE_INTERVAL - _drake_timer) <= 55.0 or (game_time >= NASHOR_SPAWN - 60.0 and _nashor_timer >= 120.0)
		var good_decision: float = (vision + teamplay + mental) / 300.0
		good_decision += 0.12 if adc_safe else -0.18
		good_decision += 0.15 if bool(jungler.get("alive", true)) else -0.12
		good_decision += 0.18 if objective_soon else 0.0

		if randf() > clampf(good_decision, 0.2, 0.86):
			_apply_failed_support_roam(side)
			support["last_support_action"] = "bad roam"
			event_log.append("%s support roamed too early" % side.to_upper())
			continue

		if objective_soon:
			support["vision_control"] = float(support.get("vision_control", 0.0)) + 1.0
			support["last_support_action"] = "objective vision"
			if randf() < 0.09:
				_score_pickoff(side, "sup")
				event_log.append("%s support got caught warding" % side.to_upper())
				continue
			event_log.append("%s support prepared objective vision" % side.to_upper())
		elif randf() < 0.45 and bool(jungler.get("alive", true)):
			support["last_support_action"] = "help jgl"
			_add_gold(side, "sup", 25)
			_add_xp(side, "sup", 45)
			event_log.append("%s support helped jungler" % side.to_upper())
		else:
			support["last_support_action"] = "roam mid"
			_register_lane_fight("mid", false)
			var roam_kill_chance: float = clampf(0.2 + teamplay / 220.0, 0.25, 0.64) * _lane_kill_multiplier("mid")
			if bool(teams[enemy]["mid"].get("alive", true)) and randf() < roam_kill_chance:
				_score_kill(side, "mid", enemy, "mid", ["sup"])
				_register_lane_fight("mid", true)
				event_log.append("%s support roam mid worked" % side.to_upper())

func _resolve_lane_duel() -> void:
	var lane: String = LANES[randi() % LANES.size()]
	var player_state: Dictionary = teams["player"][lane]
	var ai_state: Dictionary = teams["ai"][lane]
	if not bool(player_state.get("alive", true)) or not bool(ai_state.get("alive", true)):
		return

	_register_lane_fight(lane, false)
	var player_chance: float = _duel_win_chance(player_state, ai_state)
	var kill_roll := 0.24 if game_time < MID_GAME_START else 0.34
	kill_roll *= _lane_kill_multiplier(lane)
	if randf() > kill_roll:
		var pressure_side: String = "player" if randf() < player_chance else "ai"
		_add_gold(pressure_side, lane, 70)
		_add_xp(pressure_side, lane, 70)
		event_log.append("%s gained lane pressure on %s" % [pressure_side.to_upper(), lane.to_upper()])
		return

	if randf() < player_chance:
		var victim_role := _lane_victim_role("ai", lane)
		_score_kill("player", lane, "ai", victim_role, _lane_assists("player", lane))
		_register_lane_fight(lane, true)
		event_log.append("PLAYER won a %s duel" % lane.to_upper())
	else:
		var victim_role := _lane_victim_role("player", lane)
		_score_kill("ai", lane, "player", victim_role, _lane_assists("ai", lane))
		_register_lane_fight(lane, true)
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
	var killer_side: String = _other_side(side)
	for role in ROLES:
		var state: Dictionary = teams[side][role]
		if not bool(state.get("alive", true)):
			continue
		var champion: Dictionary = state.get("champion", {})
		var champion_class: String = str(champion.get("class", "fighter"))
		var chance := 0.22 if lost else 0.1
		if champion_class in ["marksman", "mage"]:
			chance += 0.18
		elif champion_class == "support" or role == "sup":
			chance += 0.16
		elif champion_class == "tank":
			chance -= 0.08
		if randf() < clampf(chance, 0.04, 0.65):
			var finisher: String = _teamfight_finisher(killer_side)
			_score_kill(killer_side, finisher, side, role, _teamfight_assists(killer_side, finisher))

func _resolve_drake() -> void:
	var side: String = _resolve_objective_fight("drake")
	drakes[side] = int(drakes.get(side, 0)) + 1
	var bonus_keys: Array[String] = ["damage", "armor", "magic_resist", "speed", "sustain"]
	var bonus_key: String = bonus_keys[randi() % bonus_keys.size()]
	team_bonus[side][bonus_key] += 0.03
	_add_team_xp(side, DRAKE_TEAM_XP)
	event_log.append("%s secured drake (+3%% %s)" % [side.to_upper(), bonus_key])

func _resolve_nashor() -> void:
	if game_time < NASHOR_SPAWN:
		return
	var side: String = _resolve_objective_fight("nashor")
	nashors[side] = int(nashors.get(side, 0)) + 1
	team_bonus[side]["baron_until"] = game_time + 180.0
	_add_team_xp(side, NASHOR_TEAM_XP)
	event_log.append("%s secured Nashor" % side.to_upper())

func _resolve_push() -> void:
	if game_time < MID_GAME_START:
		return
	var diff := get_gold_diff()
	if diff > 1400 or _has_nashor("player"):
		_resolve_push_for_side("player", false)
	elif diff < -1400 or _has_nashor("ai"):
		_resolve_push_for_side("ai", false)

func _resolve_push_for_side(side: String, after_teamfight: bool = false) -> void:
	var enemy: String = _other_side(side)
	var alive_attackers := _alive_count(side)
	var alive_defenders := _alive_count(enemy)
	if alive_attackers < 3:
		return
	var pushes := 1
	if _has_nashor(side) and randf() < 0.7:
		pushes = 2
	if after_teamfight and _has_nashor(side) and game_time >= LATE_GAME_START and alive_defenders <= 2:
		pushes = 3
	for i in range(pushes):
		var best_lane: String = LANES[randi() % LANES.size()]
		for lane in LANES:
			if towers[enemy][lane] < towers[enemy][best_lane]:
				best_lane = lane
		if towers[enemy][best_lane] < 3:
			if alive_defenders >= 4 and not _has_nashor(side) and randf() < 0.72:
				continue
			towers[enemy][best_lane] += 1
			var finisher: String = _best_alive_role(side)
			_add_gold(side, finisher, 300)
			_add_team_xp(side, TOWER_TEAM_XP)
			event_log.append("%s destroyed %s T%d" % [side.to_upper(), best_lane.to_upper(), towers[enemy][best_lane]])
		else:
			if not _can_finish(side, enemy, after_teamfight):
				continue
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

func _level_from_xp(xp: int) -> int:
	var level := 1
	for i in range(LEVEL_XP.size()):
		if xp >= LEVEL_XP[i]:
			level = i + 1
	return clampi(level, 1, 18)

func _max_level_for_time(role: String) -> int:
	var minutes := game_time / 60.0
	var cap := 6
	if minutes >= 30.0:
		cap = 18
	elif minutes >= 25.0:
		cap = 17
	elif minutes >= 20.0:
		cap = 15
	elif minutes >= 15.0:
		cap = 13
	elif minutes >= 10.0:
		cap = 10
	else:
		cap = 8
	if role == "sup":
		cap = max(6, cap - 1)
	return cap

func _update_levels() -> void:
	for side in ["player", "ai"]:
		for role in ROLES:
			var state: Dictionary = teams[side][role]
			var raw_level := _level_from_xp(int(state.get("xp", 0)))
			state["level"] = clampi(raw_level, 1, _max_level_for_time(role))

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

func _score_kill(killer_side: String, killer_role: String, victim_side: String, victim_role: String, assister_roles: Array[String] = []) -> void:
	if victim_role == "bot" and bool(teams[victim_side]["sup"].get("alive", true)) and randf() < 0.2:
		victim_role = "sup"
	if killer_role == "sup" and assister_roles.has("bot") and bool(teams[killer_side]["bot"].get("alive", true)) and randf() < 0.65:
		assister_roles.erase("bot")
		assister_roles.append("sup")
		killer_role = "bot"
	assister_roles = _valid_assists(killer_side, killer_role, assister_roles)
	teams[killer_side][killer_role]["kills"] = int(teams[killer_side][killer_role].get("kills", 0)) + 1
	var killer_name: String = str(teams[killer_side][killer_role].get("pseudo", killer_role.to_upper()))
	var victim_name: String = str(teams[victim_side][victim_role].get("pseudo", victim_role.to_upper()))
	event_log.append("KILL|%s|%s|%s|%s" % [killer_side, killer_name, victim_side, victim_name])
	_add_gold(killer_side, killer_role, 300)
	_add_xp(killer_side, killer_role, KILL_XP)
	for role in assister_roles:
		_add_assist_gold(killer_side, role)
	_kill_player(victim_side, victim_role)

func _kill_player(side: String, role: String) -> void:
	var state: Dictionary = teams[side][role]
	state["alive"] = false
	state["deaths"] = int(state.get("deaths", 0)) + 1
	state["death_timer"] = _respawn_time(state, role)

func _respawn_time(state: Dictionary, role: String) -> float:
	var base := 10.0
	if game_time >= 1800.0:
		base = 50.0
	elif game_time >= 1200.0:
		base = 40.0
	elif game_time >= 900.0:
		base = 30.0
	elif game_time >= 600.0:
		base = 20.0
	var level_modifier: float = maxf(0.0, float(state.get("level", 1)) - 6.0) * 1.25
	var fed_modifier: float = maxf(0.0, float(int(state.get("kills", 0)) - int(state.get("deaths", 0)))) * 1.75
	var role_modifier := -2.0 if role == "sup" else 0.0
	return clampf(base + level_modifier + fed_modifier + role_modifier, 8.0, 72.0)

func _add_assist_gold(side: String, role: String) -> void:
	teams[side][role]["assists"] = int(teams[side][role].get("assists", 0)) + 1
	_add_gold(side, role, ASSIST_GOLD)
	_add_xp(side, role, ASSIST_XP)

func _add_gold(side: String, role: String, amount: int) -> void:
	var state: Dictionary = teams[side][role]
	state["gold"] = int(state.get("gold", 0)) + amount
	state["unspent_gold"] = int(state.get("unspent_gold", 0)) + amount

func _add_xp(side: String, role: String, amount: int) -> void:
	var state: Dictionary = teams[side][role]
	state["xp"] = int(state.get("xp", 0)) + max(0, amount)

func _add_team_gold(side: String, amount: int) -> void:
	var alive_roles: Array[String] = []
	for role in ROLES:
		if bool(teams[side][role].get("alive", true)):
			alive_roles.append(role)
	if alive_roles.is_empty():
		alive_roles = ROLES.duplicate()
	for role in alive_roles:
		_add_gold(side, role, int(amount / alive_roles.size()))

func _add_team_xp(side: String, amount: int) -> void:
	var alive_roles: Array[String] = []
	for role in ROLES:
		if bool(teams[side][role].get("alive", true)):
			alive_roles.append(role)
	if alive_roles.is_empty():
		return
	for role in alive_roles:
		_add_xp(side, role, int(amount / alive_roles.size()))

func _valid_assists(side: String, killer_role: String, assister_roles: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for role_variant in assister_roles:
		var role := str(role_variant)
		if role == killer_role or not ROLES.has(role) or result.has(role):
			continue
		if bool(teams[side][role].get("alive", true)):
			result.append(role)
		if result.size() >= 4:
			break
	return result

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
		power += float(state.get("power", 0.0)) + float(state.get("gold", 0)) * 0.018 + float(state.get("level", 1)) * 10.0
	var bonus: Dictionary = team_bonus[side]
	power *= 1.0 + float(bonus.get("damage", 0.0)) + float(bonus.get("armor", 0.0)) * 0.35 + float(bonus.get("magic_resist", 0.0)) * 0.35 + float(bonus.get("speed", 0.0)) * 0.25 + float(bonus.get("sustain", 0.0)) * 0.4
	return power * randf_range(0.92, 1.08)

func _has_nashor(side: String) -> bool:
	return game_time < float(team_bonus[side].get("baron_until", 0.0))

func _objective_winner() -> String:
	var player_score: float = _team_fight_power("player") + _objective_vision_score("player") + randf_range(-45.0, 45.0)
	var ai_score: float = _team_fight_power("ai") + _objective_vision_score("ai") + randf_range(-45.0, 45.0)
	return "player" if randf() < _fight_win_chance(player_score, ai_score) else "ai"

func _fight_win_chance(player_power: float, ai_power: float) -> float:
	var base: float = player_power / maxf(1.0, player_power + ai_power)
	var gold_swing: float = clampf(float(get_gold_diff()) / 15000.0, -1.0, 1.0) * 0.18
	var chance: float = base + gold_swing
	return clampf(chance, 0.08, 0.92)

func _resolve_objective_fight(objective: String) -> String:
	var player_roles: Array[String] = _objective_participants("player", objective)
	var ai_roles: Array[String] = _objective_participants("ai", objective)
	if player_roles.is_empty() or ai_roles.is_empty():
		return _objective_winner()

	var player_power: float = _team_fight_power_for_roles("player", player_roles) + _objective_vision_score("player") + randf_range(-45.0, 45.0)
	var ai_power: float = _team_fight_power_for_roles("ai", ai_roles) + _objective_vision_score("ai") + randf_range(-45.0, 45.0)
	var player_chance: float = _fight_win_chance(player_power, ai_power)
	var winner_side := "player" if randf() < player_chance else "ai"
	var loser_side := _other_side(winner_side)
	var winner_roles: Array[String] = player_roles if winner_side == "player" else ai_roles
	var loser_roles: Array[String] = ai_roles if winner_side == "player" else player_roles
	var label := "drake" if objective == "drake" else "Nashor"
	event_log.append("%s won %dv%d around %s" % [winner_side.to_upper(), winner_roles.size(), loser_roles.size(), label])
	_resolve_objective_fight_deaths(winner_side, winner_roles, loser_roles, false, objective)
	_resolve_objective_fight_deaths(loser_side, loser_roles, winner_roles, true, objective)
	_add_team_gold(winner_side, 240 if objective == "drake" else 420)
	return winner_side

func _objective_participants(side: String, objective: String) -> Array[String]:
	var roles: Array[String] = []
	var join_chance: Dictionary = {}
	if objective == "drake":
		if game_time < MID_GAME_START:
			join_chance = {"top": 0.18, "jgl": 0.95, "mid": 0.86, "bot": 0.9, "sup": 0.93}
		else:
			join_chance = {"top": 0.82, "jgl": 0.96, "mid": 0.94, "bot": 0.94, "sup": 0.96}
	else:
		join_chance = {"top": 0.9, "jgl": 0.98, "mid": 0.96, "bot": 0.95, "sup": 0.98}

	for role in ROLES:
		if not bool(teams[side][role].get("alive", true)):
			continue
		if randf() <= float(join_chance.get(role, 0.75)):
			roles.append(role)

	var minimum_roles := 4 if objective == "drake" and game_time < MID_GAME_START else 0
	if objective == "drake" and game_time >= MID_GAME_START:
		minimum_roles = 4
	elif objective == "nashor":
		minimum_roles = 4
	if minimum_roles > 0 and roles.size() < minimum_roles:
		for role in ["jgl", "mid", "bot", "sup"]:
			if bool(teams[side][role].get("alive", true)) and not roles.has(role):
				roles.append(role)
			if roles.size() >= minimum_roles:
				break
	if roles.size() < minimum_roles and bool(teams[side]["top"].get("alive", true)) and not roles.has("top"):
		roles.append("top")
	return roles

func _team_fight_power_for_roles(side: String, roles: Array[String]) -> float:
	var power: float = 0.0
	for role in roles:
		var state: Dictionary = teams[side][role]
		power += float(state.get("power", 0.0)) + float(state.get("gold", 0)) * 0.018 + float(state.get("level", 1)) * 10.0
	var bonus: Dictionary = team_bonus[side]
	power *= 1.0 + float(bonus.get("damage", 0.0)) + float(bonus.get("armor", 0.0)) * 0.35 + float(bonus.get("magic_resist", 0.0)) * 0.35 + float(bonus.get("speed", 0.0)) * 0.25 + float(bonus.get("sustain", 0.0)) * 0.4
	return power

func _resolve_objective_fight_deaths(side: String, roles: Array[String], killer_roles: Array[String], lost: bool, objective: String) -> void:
	var killer_side := _other_side(side)
	var killer_pool: Array[String] = _alive_roles_from(killer_side, killer_roles)
	if killer_pool.is_empty():
		killer_pool = _alive_roles_from(killer_side, ROLES)
	var base_chance := 0.22 if lost else 0.08
	if objective == "nashor":
		base_chance += 0.12
	elif game_time >= MID_GAME_START:
		base_chance += 0.08
	for role in roles:
		var state: Dictionary = teams[side][role]
		if not bool(state.get("alive", true)):
			continue
		var chance := base_chance
		if role == "sup":
			chance += 0.14
		elif role == "bot":
			chance += 0.08
		elif role == "top":
			chance -= 0.04
		if randf() < clampf(chance, 0.04, 0.68):
			var finisher := _objective_finisher(killer_side, killer_pool)
			_score_kill(killer_side, finisher, side, role, _objective_assists(killer_side, killer_pool, finisher))

func _objective_finisher(side: String, roles: Array[String]) -> String:
	var candidates: Array[String] = []
	for role in roles:
		if role != "sup" and bool(teams[side][role].get("alive", true)):
			candidates.append(role)
	if candidates.is_empty():
		candidates = _alive_roles_from(side, roles)
	if candidates.is_empty():
		return _best_alive_role(side)
	return candidates[randi() % candidates.size()]

func _objective_assists(side: String, roles: Array[String], finisher: String) -> Array[String]:
	var assists: Array[String] = []
	for role in roles:
		if role == finisher:
			continue
		if bool(teams[side][role].get("alive", true)) and randf() < (0.86 if role == "sup" else 0.58):
			assists.append(role)
	return assists

func _objective_vision_score(side: String) -> float:
	var support: Dictionary = teams[side]["sup"]
	var stats: Dictionary = support.get("stats", {})
	var score: float = float(support.get("vision_control", 0.0)) * 34.0
	if bool(support.get("alive", true)):
		score += _grade(stats.get("vision", "C")) * 0.45
	support["vision_control"] = maxf(0.0, float(support.get("vision_control", 0.0)) - 0.45)
	return score

func _support_is_helping_gank(side: String, lane: String) -> bool:
	var support: Dictionary = teams[side]["sup"]
	if not bool(support.get("alive", true)):
		return false
	if lane == "bot":
		return true
	return str(support.get("last_support_action", "")) in ["roam mid", "help jgl", "objective vision"]

func _lane_victim_role(side: String, lane: String) -> String:
	if lane == "bot" and bool(teams[side]["sup"].get("alive", true)) and randf() < 0.32:
		return "sup"
	return lane

func _lane_assists(side: String, lane: String) -> Array[String]:
	var assists: Array[String] = []
	if lane == "bot" and bool(teams[side]["sup"].get("alive", true)):
		assists.append("sup")
	elif randf() < 0.18 and bool(teams[side]["jgl"].get("alive", true)):
		assists.append("jgl")
	return assists

func _score_pickoff(victim_side: String, victim_role: String) -> void:
	var killer_side := _other_side(victim_side)
	var finisher := _best_alive_role(killer_side)
	var assists: Array[String] = []
	if finisher != "jgl" and bool(teams[killer_side]["jgl"].get("alive", true)) and randf() < 0.45:
		assists.append("jgl")
	if victim_role == "bot" and finisher != "sup" and bool(teams[killer_side]["sup"].get("alive", true)) and randf() < 0.5:
		assists.append("sup")
	_score_kill(killer_side, finisher, victim_side, victim_role, assists)

func _apply_failed_support_roam(side: String) -> void:
	var adc: Dictionary = teams[side]["bot"]
	if bool(adc.get("alive", true)):
		adc["cs"] = max(0, int(adc.get("cs", 0)) - 2)
		adc["gold"] = max(0, int(adc.get("gold", 0)) - 45)
		adc["unspent_gold"] = max(0, int(adc.get("unspent_gold", 0)) - 45)
		if randf() < 0.12:
			_score_pickoff(side, "bot")
	var support: Dictionary = teams[side]["sup"]
	if bool(support.get("alive", true)) and randf() < 0.16:
		_score_pickoff(side, "sup")

func _best_alive_role(side: String) -> String:
	var best_role: String = "top"
	var best_gold: int = -1
	for role in ROLES:
		var state: Dictionary = teams[side][role]
		if bool(state.get("alive", true)) and int(state.get("gold", 0)) > best_gold:
			best_gold = int(state.get("gold", 0))
			best_role = role
	return best_role

func _teamfight_finisher(side: String) -> String:
	var candidates: Array[String] = []
	for role in ROLES:
		if role == "sup":
			continue
		if bool(teams[side][role].get("alive", true)):
			candidates.append(role)
	if candidates.is_empty() and bool(teams[side]["sup"].get("alive", true)):
		return "sup"
	if candidates.is_empty():
		return _best_alive_role(side)
	return candidates[randi() % candidates.size()]

func _teamfight_assists(side: String, finisher: String) -> Array[String]:
	var assists: Array[String] = []
	for role in ROLES:
		if role == finisher:
			continue
		if bool(teams[side][role].get("alive", true)) and randf() < (0.82 if role == "sup" else 0.48):
			assists.append(role)
	return assists

func _teamfight_interval() -> float:
	if game_time < MID_GAME_START:
		return 99999.0
	if game_time < LATE_GAME_START:
		return 95.0
	return 75.0

func _gank_interval() -> float:
	if game_time < MID_GAME_START:
		return 58.0
	if game_time < LATE_GAME_START:
		return 48.0
	return 42.0

func _duel_interval() -> float:
	if game_time < MID_GAME_START:
		return 70.0
	if game_time < LATE_GAME_START:
		return 62.0
	return 55.0

func _tick_lane_fight_heat(delta: float) -> void:
	var decay := 0.18
	if game_time >= MID_GAME_START:
		decay = 0.55
	for lane in LANES:
		_lane_fight_heat[lane] = maxf(0.0, float(_lane_fight_heat.get(lane, 0.0)) - decay * delta / 60.0)

func _register_lane_fight(lane: String, killed: bool) -> void:
	if not _lane_fight_heat.has(lane):
		return
	var amount := 0.28
	if killed:
		amount = 0.9
	if lane == "mid":
		amount *= 1.25
	if game_time >= MID_GAME_START:
		amount *= 0.45
	_lane_fight_heat[lane] = clampf(float(_lane_fight_heat.get(lane, 0.0)) + amount, 0.0, 4.0)

func _lane_kill_multiplier(lane: String) -> float:
	var heat := float(_lane_fight_heat.get(lane, 0.0))
	if game_time >= MID_GAME_START:
		var comeback := clampf((game_time - MID_GAME_START) / 300.0, 0.0, 1.0)
		return lerpf(clampf(1.0 - heat * 0.08, 0.72, 1.0), 1.0, comeback)
	var reduction := heat * (0.18 if lane == "mid" else 0.13)
	return clampf(1.0 - reduction, 0.38 if lane == "mid" else 0.48, 1.0)

func _alive_count(side: String) -> int:
	var count := 0
	for role in ROLES:
		if bool(teams[side][role].get("alive", true)):
			count += 1
	return count

func _alive_roles_from(side: String, roles: Array) -> Array[String]:
	var result: Array[String] = []
	for role_variant in roles:
		var role := str(role_variant)
		if ROLES.has(role) and bool(teams[side][role].get("alive", true)):
			result.append(role)
	return result

func _can_finish(side: String, enemy: String, after_teamfight: bool) -> bool:
	if game_time < NASHOR_SPAWN:
		return false
	var alive_defenders := _alive_count(enemy)
	if alive_defenders > 2:
		return false
	if not after_teamfight and not _has_nashor(side) and game_time < LATE_GAME_START:
		return false
	if alive_defenders == 2 and not _has_nashor(side) and randf() < 0.65:
		return false
	return true

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
