extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const StatusIcon = Ids.StatusIcon
const Spell = Ids.Spell
const Side = Ids.Side
const Stat = Ids.Stat
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Random = preload("res://scripts/gameplay/legacy_random.gd")
const Rules = preload("res://scripts/gameplay/combat_rules.gd")
const Spells = preload("res://scripts/gameplay/spell_rules.gd")
const Effects = preload("res://scripts/gameplay/status_effects.gd")
const Fixtures = preload("res://tests/battle_checks.gd")


func actor(type: int, metadata: Dictionary, table: Dictionary, id: int = 2000):
	var unit := Unit.new()
	unit.configure({"instance_id": id, "unit_type": type, "story_group": 5, "spawn_flag": 5, "side_id": 0}, metadata, table)
	return unit


func effect_rows(unit) -> Array:
	var rows: Array = []
	for effect in unit.effects: rows.append(PackedInt32Array([int(effect["slot"]), int(effect["value"]), int(effect["duration"]), 0, int(effect["icon"])]))
	return rows


func source_effects(values: Array) -> Array:
	var result: Array = []
	for row: Array in values: result.append(PackedInt32Array(row))
	return result


func fixture(world: Dictionary, metadata: Dictionary, table: Dictionary) -> Array:
	var pair: Array = Fixtures.new().fixture(world, metadata, table)
	var game = pair[0]
	var caster = actor(5, metadata, table)
	for slot in range(47, 55): caster.base_stats[slot] = 7
	caster.base_stats[Stat.MAX_MANA] = 1000
	caster.recalculate(table)
	caster.move_to(Vector2i(23, 20))
	caster.reset_interpolation()
	game.units.append(caster)
	game.party.append(caster)
	game.collision.occupy(caster.instance_id, caster.cell, caster.footprint)
	pair[1].begin(game, [1001])
	pair[1].select(caster.instance_id)
	return pair


func run(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/legacy/magic_reference.json"))
	for case: Dictionary in reference["payloads"]:
		var caster = actor(int(case["type"]), metadata, table)
		caster.stats = PackedInt32Array(case["stats"])
		var id: int = int(case["spell"])
		checks.check(Spells.learned(caster, id, metadata) and Spells.cost(caster, id, metadata) == int(case["cost"]), "spell %d availability and mana match m.a()" % id)
		checks.check(Spells.payload(caster, id, metadata) == PackedInt32Array(case["payload"]), "spell %d payload matches q.q_a()" % id)
	for index in range(reference["damage"].size()):
		var case: Dictionary = reference["damage"][index]
		var caster = actor(int(case["type"]), metadata, table)
		var defender = actor(int(case["defender_type"]), metadata, table, 2001)
		caster.stats = PackedInt32Array(case["attacker"])
		defender.stats = PackedInt32Array(case["defender"])
		caster.base_stats[Stat.LEVEL] = caster.stats[Stat.LEVEL]
		if index == 7: defender.base_stats[Stat.TACTICS] = 26
		if index == 12: defender.base_stats[Stat.DEFENSE] = 101
		defender.dead = bool(case["was_dead"])
		var rng := Random.new(int(case["seed"]))
		var hit: Dictionary = Rules.apply(caster, defender, PackedInt32Array(case["payload"]), rng, table, 2)
		checks.check(caster.stats == PackedInt32Array(case["attacker_after"]) and defender.stats == PackedInt32Array(case["defender_after"]), "full q.a(q) HP/stats match Java case %d" % index)
		checks.check(effect_rows(defender) == source_effects(case["effects"]) and defender.dead == case["dead"] and defender.shattered == case["shattered"] and hit["counter"] == case["counter"], "procs, revive, corpse and counter match Java case %d" % index)
		checks.check(rng.next_signed() == int(case["next_int"]), "full damage RNG order matches Java case %d" % index)
	var poisoned = actor(0, metadata, table)
	poisoned.stats[Stat.HP] = 10
	poisoned.stats[Stat.MANA] = 0
	Effects.add(poisoned, table, Stat.POISON_DAMAGE, 4, 8, StatusIcon.POISON)
	Effects.add(poisoned, table, Stat.MAX_ACTION_POINTS, -1, 3, StatusIcon.SLOW)
	Effects.add(poisoned, table, Stat.MAX_ACTION_POINTS, -2, 2, StatusIcon.SLOW)
	Effects.add(poisoned, table, Stat.MAX_ACTION_POINTS, -1, 3, StatusIcon.SLOW)
	var rng := Random.new(20261026)
	for turn: Dictionary in reference["turns"]:
		Effects.start_turn(poisoned, table, rng)
		checks.check(poisoned.stats == PackedInt32Array(turn["stats"]) and effect_rows(poisoned) == source_effects(turn["effects"]), "poison decay, mana regen, duration and strongest merge match q.d()")
	for index in range(reference["roots"].size()): checks.check(Spells.integer_root(index) == int(reference["roots"][index]), "original integer root %d" % index)
	for case: Dictionary in reference["walls"]:
		var caster = actor(5, metadata, table)
		caster.set_pixel_position(Vector2(328, 328))
		caster.stats[Stat.DARK_FIRE_MAGIC] = int(case["rank"]) * 2 + 1
		var positions: Array[Vector2i] = Spells.wall_positions(caster, Vector2i(case["target"][0], case["target"][1]), metadata)
		var expected: Array[Vector2i] = []
		for point: Array in case["points"]: expected.append(Vector2i(point[0], point[1]))
		checks.check(positions == expected, "fire wall footprint matches actual n.void_a() rank %d" % int(case["rank"]))
	for spell in range(15):
		var pair := fixture(world, metadata, table)
		var battle = pair[1]
		var caster = battle.unit(2000)
		var target = battle.session.hero if spell in [Spell.HEAL, Spell.VAMPIRISM, Spell.HASTE, Spell.BLESS, Spell.STONE_SKIN] else battle.unit(1001)
		var mana: int = caster.stats[Stat.MANA]
		var cost: int = Spells.cost(caster, spell, metadata)
		checks.check(battle.cast(spell, target.cell), "spell %d submits through validated command queue" % spell)
		checks.check(not battle.cast(spell, target.cell), "spell %d rejects duplicate while busy" % spell)
		for i in range(300):
			if not battle.busy(): break
			battle.advance(0.062)
		var impacts: int = 0
		for event in battle.events:
			if event["event"] == "spell_impact": impacts += 1
		checks.check(impacts == 1 and caster.stats[Stat.MANA] == mana - cost and not battle.busy(), "spell %d resolves once, charges exact mana and finishes" % spell)
		if spell in [Spell.MIASMA, Spell.FIRE_WALL]: checks.check(not battle.hazards.is_empty(), "persistent spell creates round hazard")
		if spell in [Spell.SLOW, Spell.VAMPIRISM, Spell.PETRIFY, Spell.HASTE, Spell.BLESS, Spell.STONE_SKIN]: checks.check(not target.effects.is_empty(), "status spell applies original modifier")
	_limits(checks, world, metadata, table)
	_interactions(checks, world, metadata, table)
	_fps(checks, world, metadata, table)
	_meteor(checks, world, metadata, table)


func _meteor(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var mage = actor(Ids.UnitKind.RADIUS, metadata, table)
	mage.stats[Stat.DARK_FIRE_MAGIC] = 3
	checks.check(not Spells.learned(mage, Spell.METEOR, metadata), "Meteor remains unavailable below the original fire-school threshold")
	mage.stats[Stat.DARK_FIRE_MAGIC] = 4
	checks.check(Spells.learned(mage, Spell.METEOR, metadata), "party mage can learn Meteor at fire-school value four")
	var pair := fixture(world, metadata, table)
	var battle = pair[1]
	var target = battle.unit(1001)
	var impacts: Array[int] = []
	battle.spell_impact.connect(func(spell: int, _cell: Vector2i, tick: int):
		if spell == Spell.METEOR: impacts.append(tick)
	)
	checks.check(battle.cast(Spell.METEOR, target.cell), "Meteor submits through the normal party casting path")
	for i in range(100):
		if battle.current.get("phase") == "flight": break
		battle.advance(0.062)
	var launched: int = battle.tick_count
	var hp: int = target.stats[Stat.HP]
	for i in range(13): battle.advance(0.062)
	checks.check(impacts.is_empty() and target.stats[Stat.HP] == hp, "Meteor cannot hit before the accelerating stone reaches the target")
	battle.advance(0.062)
	checks.check(impacts == [launched + 14], "Meteor emits exactly one impact after fourteen ticks without drawing a frame")


func _limits(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var pair := fixture(world, metadata, table)
	var battle = pair[1]
	var caster = battle.unit(2000)
	var enemy = battle.unit(1001)
	var mana: int = caster.stats[Stat.MANA]
	caster.stats[Stat.MANA] = 0
	checks.check(not battle.cast(0, enemy.cell) and battle.queue.is_empty(), "insufficient mana rejects cast without queue or cost")
	caster.stats[Stat.MANA] = mana
	checks.check(not battle.cast(0, battle.session.hero.cell) and not battle.cast(1, enemy.cell) and not battle.cast(11, battle.session.hero.cell), "spells enforce hostile/friendly target roles")
	checks.check(not battle.cast(0, battle.arena.end) and not battle.cast(-1, enemy.cell) and not battle.cast(15, enemy.cell), "invalid spell and outside arena rejected")
	battle.session.hero.dead = true
	battle.session.hero.stats[Stat.HP] = 0
	checks.check(battle.cast(1, battle.session.hero.cell), "healing can target recoverable ally corpse")
	for i in range(100):
		if not battle.busy(): break
		battle.advance(0.062)
	checks.check(not battle.session.hero.dead and battle.session.hero.stats[Stat.HP] == 1, "healing revives with original one HP, not full heal")
	Effects.add(caster, table, Stat.STUN, 1, 2, StatusIcon.STUN)
	checks.check(not battle.eligible(caster), "stun prevents acting")
	Effects.start_turn(caster, table, battle.rng)
	Effects.start_turn(caster, table, battle.rng)
	checks.check(caster.stats[Stat.STUN] == 0, "finite stun expires rather than permanently stalling")


func _fps(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	for spell in range(15):
		var baseline: Dictionary = {}
		for fps in [30, 60, 144]:
			var pair := fixture(world, metadata, table)
			var battle = pair[1]
			var target = battle.session.hero if spell in [Spell.HEAL, Spell.VAMPIRISM, Spell.HASTE, Spell.BLESS, Spell.STONE_SKIN] else battle.unit(1001)
			battle.cast(spell, target.cell)
			for i in range(fps * 10):
				if not battle.busy(): break
				battle.advance(1.0 / fps)
			var state := {"caster": battle.unit(2000).snapshot(), "target": battle.unit(1001).snapshot(), "rng": battle.rng.snapshot(), "events": battle.events}
			if baseline.is_empty(): baseline = state
			checks.check(state == baseline, "spell %d animation/flight/impact and RNG match at %d FPS" % [spell, fps])


func _interactions(checks, world: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	var pair := fixture(world, metadata, table)
	var game = pair[0]
	var battle = pair[1]
	var enemy = battle.unit(1001)
	# A second hostile keeps the battle alive while testing corpses and reactions.
	var second = actor(14, metadata, table, 2002)
	second.side_id = Side.HOSTILE
	second.encounter_enabled = true
	second.spawn_flag = 0
	second.move_to(enemy.cell + Vector2i.RIGHT * 3)
	second.reset_interpolation()
	game.units.append(second)
	battle.participants.append(second.instance_id)
	battle.state[second.instance_id] = battle.state[enemy.instance_id].duplicate(true)
	game.collision.occupy(second.instance_id, second.cell, second.footprint)
	enemy.dead = true
	enemy.stats[Stat.HP] = 0
	checks.check(battle.cast(0, enemy.cell), "offensive spell can destroy hostile corpse")
	for i in range(150):
		if not battle.busy(): break
		battle.advance(0.062)
	checks.check(enemy.shattered and not game.collision.units.has(enemy.instance_id) and not battle.cast_plan(battle.unit(2000), 1, enemy.cell)["valid"], "destroyed corpse is nonblocking and cannot be revived")
	pair = fixture(world, metadata, table)
	game = pair[0]
	battle = pair[1]
	enemy = battle.unit(1001)
	var archer = game.party[1]
	archer.base_stats[Stat.ARCHERY] = 7
	archer.recalculate(table)
	enemy.base_stats[Stat.MAX_HP] = 1000
	enemy.recalculate(table)
	enemy.stats[Stat.HP] = enemy.stats[Stat.MAX_HP]
	battle.select(archer.instance_id)
	checks.check(battle.attack_many([enemy.instance_id]), "rank-seven archer queues original three-shot series")
	for i in range(300):
		if not battle.busy(): break
		battle.advance(0.062)
	var hits: int = 0
	for event in battle.events:
		if event["event"] == "hit" and int(event["actor"]) == archer.instance_id: hits += 1
	checks.check(hits == 3 and battle.current_side == Side.PARTY, "all three shots execute before another actor/side")
	pair = fixture(world, metadata, table)
	game = pair[0]
	battle = pair[1]
	enemy = battle.unit(1001)
	enemy.base_stats[Stat.TACTICS] = 26
	enemy.recalculate(table)
	game.hero.move_to(Vector2i(21, 20))
	game.hero.reset_interpolation()
	game.collision.place(game.hero.instance_id, game.hero.cell, game.hero.footprint)
	battle.select(game.hero.instance_id)
	checks.check(battle.attack(enemy.instance_id), "reaction fixture submits melee")
	for i in range(250):
		if not battle.busy(): break
		battle.advance(0.062)
	var counter: bool = false
	for event in battle.events:
		if event["event"] == "command_started" and event.get("reaction", false): counter = true
	checks.check(counter, "tactics counter executes from other side despite normal eligibility lock")
	pair = fixture(world, metadata, table)
	game = pair[0]
	battle = pair[1]
	enemy = battle.unit(1001)
	enemy.petrify_rounds = 1
	battle.end_side()
	for i in range(30):
		if battle.current_side == Side.PARTY and battle.round_number == 2: break
		battle.advance(0.062)
	checks.check(battle.round_number == 2 and enemy.petrify_rounds == 0 and battle.current_side == Side.PARTY, "one-round petrification skips enemy turn and expires on round boundary")
	battle.hazards.append({"spell": 8, "actor": 2000, "cell": enemy.cell, "duration": 2})
	var hp: int = enemy.stats[Stat.HP]
	battle._tick_hazards()
	checks.check(enemy.stats[Stat.HP] < hp and battle.hazards.size() == 1, "miasma damages targets at round boundary")
	battle._tick_hazards()
	checks.check(battle.hazards.is_empty(), "persistent hazard expires after its final damage tick")
