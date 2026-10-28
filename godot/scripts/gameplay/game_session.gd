extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const StoryGroup = Ids.StoryGroup
const UnitKind = Ids.UnitKind
const Facing = Ids.Facing
const Side = Ids.Side
## Rules/state contain no rendering, input or time dependency.

signal changed
signal location_changed
const Travel = preload("res://scripts/gameplay/world_travel.gd")
const Random = preload("res://scripts/gameplay/legacy_random.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Collision = preload("res://scripts/gameplay/map_collision.gd")
const Pathfinder = preload("res://scripts/gameplay/grid_pathfinder.gd")
const SceneData = preload("res://scripts/gameplay/legacy_scene_data.gd")
const SpawnState = Ids.SpawnState
const Inventory = preload("res://scripts/gameplay/inventory_rules.gd")

var map: Dictionary
var world_data: Dictionary
var current_scene: Dictionary
var location_id: int = 0
var entry_id: int = 0
var travel_error: String = ""
var world_rng = Random.new(20261027)
var gate_choices: Array = []
var campaign_completed: bool = false
var rain_remaining: float = 0
var rain_elapsed: float = 0
var rain_layers: int = 0
var last_rumour: int = -1
var flags: Dictionary
var quests: Array:
	get: return flags["a"]
var triggers: Array:
	get: return flags["b"]
var spawn_states: Array:
	get: return flags["d"]
var tutorial_seen: Array:
	get: return flags["f"]
var dungeon_seeds: Array
var hero: Unit
var collision := Collision.new()
var pathfinder := Pathfinder.new()
var commands: Array[Dictionary] = []
var units: Array[Unit] = []
var party: Array[Unit] = []
var definitions: Dictionary
var ability_table: Dictionary
var demo_party: bool = false
var god_mode: bool = false
var simulation_tick: int = 0
var mode: StringName = &"exploration"
var reward_table: Dictionary = {}
var gold: int = 0
var inventory: Array = []
var next_item_id: int = 1000000
var pickup_flags: Array:
	get: return flags["c"]


func start(world: Dictionary, metadata: Dictionary, table: Dictionary, rewards: Dictionary = {}) -> bool:
	var initial: Dictionary = metadata["new_game"]
	definitions = metadata
	world_data = world
	location_id = 0
	entry_id = 0
	travel_error = ""
	world_rng = Random.new(20261027)
	last_rumour = -1
	gate_choices = []
	campaign_completed = false
	rain_remaining = 0
	rain_elapsed = 0
	rain_layers = 0
	ability_table = table
	reward_table = rewards
	gold = 0
	inventory.clear()
	next_item_id = 1000000
	units.clear()
	party.clear()
	demo_party = false
	god_mode = false
	simulation_tick = 0
	mode = &"exploration"
	map = {}
	flags = initial["flags"].duplicate(true)
	dungeon_seeds = initial["dungeon_seeds"].duplicate()
	for candidate: Dictionary in world["maps"]:
		if str(candidate["name"]) == str(initial["map"]):
			map = candidate
	if map.is_empty():
		return false
	hero = Unit.new()
	hero.configure(initial["hero"], metadata, table)
	var entry: Dictionary = metadata["map_1_entries"][int(initial["entry"])]
	hero.set_pixel_position(Vector2(float(entry["position_pixels"][0]), float(entry["position_pixels"][1])))
	hero.facing = int(entry["facing"])
	hero.reset_interpolation()
	units.append(hero)
	party.append(hero)
	collision.configure(map, world["constants"]["tile_image_ids"], metadata)
	commands.clear()
	if not collision.place(hero.instance_id, hero.cell, hero.footprint):
		push_error("Original entry footprint is obstructed")
		return false
	# m.g(): d==2 skips construction; n.a(): d==1 is hidden and nonblocking.
	var scene_index: int = int(initial["map"]) - 1
	current_scene = world["scenes"][scene_index].duplicate(true)
	current_scene["pickups"] = metadata["economy"]["pickups"][scene_index].duplicate(true)
	var spawns: Array = world["scenes"][scene_index]["units"]
	for index in range(spawns.size()):
		var spawn: Dictionary = SceneData.spawn(spawns[index])
		var flag: int = int(spawn["spawn_flag"])
		if int(spawn_states[flag]) == SpawnState.REMOVED:
			continue
		var unit := Unit.new()
		unit.configure({"instance_id": 1000 + index, "unit_type": spawn["unit_type"], "story_group": spawn["story_group"], "spawn_flag": flag, "side_id": Ids.Side.HOSTILE}, metadata, table)
		unit.set_pixel_position(spawn["position_pixels"])
		unit.facing = int(spawn["facing"])
		unit.reset_interpolation()
		unit.encounter_enabled = bool(spawn["encounter_enabled"])
		unit.story_refs.assign(spawn["story_refs"])
		units.append(unit)
		if is_active(unit) and not collision.occupy(unit.instance_id, unit.cell, unit.footprint):
			push_error("NPC spawn footprint outside map: %d" % index)
			return false
	Inventory.sync_party(self)
	rebuild_paths()
	changed.emit()
	return true


func rebuild_paths() -> void:
	pathfinder.build(collision, hero.cell, hero.footprint, hero.instance_id)


func step(next: Vector2i) -> bool:
	if mode != &"exploration": return false
	if (next - hero.cell).length_squared() != 1 or not collision.place(hero.instance_id, next, hero.footprint):
		return false
	commands.append({"command": "step", "from": [hero.cell.x, hero.cell.y], "to": [next.x, next.y]})
	hero.move_to(next)
	changed.emit()
	return true


func snapshot(include_commands: bool = true) -> Dictionary:
	var actors: Array = []
	var party_ids: Array[int] = []
	for unit in units:
		actors.append(unit.snapshot())
	for unit in party:
		party_ids.append(unit.instance_id)
	var items: Array = []
	for item in inventory: items.append(item.snapshot())
	return {"format": "allods-debug-v4", "mode": str(mode), "gold": gold, "map": str(map["name"]), "location_id": location_id, "entry_id": entry_id, "world_rng": world_rng.snapshot(), "last_rumour": last_rumour, "gate_choices": gate_choices.duplicate(), "campaign_completed": campaign_completed, "weather": {"remaining": rain_remaining, "elapsed": rain_elapsed, "layers": rain_layers}, "simulation_tick": simulation_tick, "hero": hero.snapshot(), "units": actors, "party_ids": party_ids, "inventory": items, "next_item_id": next_item_id, "demo_party": demo_party, "flags": flags.duplicate(true), "dungeon_seeds": dungeon_seeds.duplicate(), "commands": commands.duplicate(true) if include_commands else []}


func pickups() -> Array:
	var result: Array = []
	for pickup: Dictionary in current_scene.get("pickups", []):
		if int(pickup_flags[int(pickup["pickup_id"])]) == 0: result.append(pickup)
	return result


func travel(map_id: int, entrance_id: int) -> bool:
	return Travel.enter(self, map_id, entrance_id)


func collect_nearby() -> Dictionary:
	if mode != &"exploration": return {}
	var candidates: Array = pickups()
	candidates.reverse()
	for pickup: Dictionary in candidates:
		var position: Array = pickup["position_pixels"]
		if hero.position_pixels.x < position[0] or hero.position_pixels.x > position[0] + 32 or hero.position_pixels.y < position[1] or hero.position_pixels.y > position[1] + 32: continue
		pickup_flags[int(pickup["pickup_id"])] = 1
		gold += int(pickup["gold"])
		for id in pickup["items"]: Inventory.add(self, int(id))
		commands.append({"command": "pickup", "pickup_id": int(pickup["pickup_id"]), "tick": simulation_tick})
		changed.emit()
		return pickup.duplicate(true)
	return {}


func is_active(unit: Unit) -> bool:
	return unit in party or int(spawn_states[unit.spawn_flag]) == SpawnState.VISIBLE


func set_spawn_state(flag: int, state: int) -> void:
	if flag < 0 or flag >= spawn_states.size() or state < 0 or state > 2:
		return
	spawn_states[flag] = state
	for unit in units:
		if unit.spawn_flag != flag or unit in party:
			continue
		if is_active(unit):
			collision.occupy(unit.instance_id, unit.cell, unit.footprint)
		else:
			collision.remove(unit.instance_id)
	changed.emit()


func render_records(alpha: float = 1.0) -> Array:
	var records: Array = []
	for unit in units:
		if is_active(unit):
			records.append(unit.render_at(unit.previous_position.lerp(unit.position_pixels, alpha)))
	return records


func can_move_pixels(unit: Unit, point: Vector2, direction: int) -> bool:
	# n.boolean_a(int,int): sprite map bounds + inclusive physical box /16.
	var definition: Dictionary = definitions["exploration"]["units"][unit.unit_type]
	var size: Array = definition["frame_sizes"][direction]
	var origin: Array = definition["origins"][direction]
	if point.x < float(origin[0]) or point.y < float(origin[1]) or point.x + float(size[0]) - float(origin[0]) >= collision.width * 16 or point.y + float(size[1]) - float(origin[1]) >= collision.height * 16:
		return false
	var first := Vector2i(int((point.x - unit.collision_half_extents.x) / 16.0), int((point.y - unit.collision_half_extents.y) / 16.0))
	var last := Vector2i(int((point.x + unit.collision_half_extents.x) / 16.0), int((point.y + unit.collision_half_extents.y) / 16.0))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			if collision.is_terrain_blocked(Vector2i(x, y)):
				return false
	var box := Rect2i(first, last - first + Vector2i.ONE)
	for other in units:
		# The original party follows through its own trail without mutual blocking.
		if other == unit or other in party or other.dead or not other.collision_enabled or not is_active(other):
			continue
		if box.intersects(Rect2i(other.cell, other.footprint)):
			return false
	return true


func move_pixels(unit: Unit, delta: Vector2) -> bool:
	if mode != &"exploration":
		return false
	var amount: float = absf(delta.x) + absf(delta.y)
	if amount <= 0 or amount > float(definitions["exploration"]["pixels_per_tick"]) or (delta.x != 0 and delta.y != 0):
		return false
	var direction: int = (Facing.LEFT if delta.x < 0 else Facing.RIGHT) if delta.x != 0 else (Facing.UP if delta.y < 0 else Facing.DOWN)
	unit.facing = direction
	if not can_move_pixels(unit, unit.position_pixels + delta, direction):
		return false
	commands.append({"command": "pixel_step", "tick": simulation_tick, "instance_id": unit.instance_id, "from": [unit.position_pixels.x, unit.position_pixels.y], "delta": [delta.x, delta.y]})
	unit.set_pixel_position(unit.position_pixels + delta)
	unit.walking = true
	collision.occupy(unit.instance_id, unit.cell, unit.footprint)
	return true


func add_demo_companion() -> Unit:
	if party.size() > 1:
		return party[1]
	var companion: Unit
	for candidate in units:
		if candidate.unit_type == UnitKind.LI and candidate.story_group == StoryGroup.LI:
			companion = candidate
			break
	if companion == null:
		return null
	# Explicit test fixture. Narrative recruitment and teleporting script commands
	# are stage five, so the ordinary new game never calls this method.
	for offset in [Vector2(40, 0), Vector2(-40, 0), Vector2(0, 40), Vector2(0, -40)]:
		var point: Vector2 = hero.position_pixels + offset
		if not can_move_pixels(companion, point, hero.facing):
			continue
		companion.set_pixel_position(point)
		companion.reset_interpolation()
		companion.side_id = Side.PARTY
		companion.facing = hero.facing
		party.append(companion)
		spawn_states[companion.spawn_flag] = 0
		collision.occupy(companion.instance_id, companion.cell, companion.footprint)
		demo_party = true
		commands.append({"command": "demo_companion", "instance_id": companion.instance_id})
		changed.emit()
		return companion
	return null


func world_travel_unlocked() -> bool:
	# Scene 2, script 22: Kurt joins, city exit 23 opens, quest 14 completes.
	# The completed quest remains valid if Kurt later leaves the party.
	return int(quests[Ids.Quest.CITY_CERTIFICATE]) == Ids.QuestState.COMPLETED


func start_rain(seconds: float, layers: int = 1) -> void:
	rain_remaining = maxf(0, seconds)
	rain_elapsed = 0
	rain_layers = clampi(layers, 0, 2)

func advance_weather(delta: float) -> void:
	if rain_remaining <= 0: return
	var elapsed: float = minf(maxf(delta, 0), rain_remaining)
	rain_remaining -= elapsed
	rain_elapsed += elapsed
