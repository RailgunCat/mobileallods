extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Spell = Ids.Spell
const Stat = Ids.Stat
const Spells = preload("res://scripts/gameplay/spell_rules.gd")
const Visuals = preload("res://scripts/gameplay/spell_presentation.gd")
const Feedback = preload("res://scripts/gameplay/combat_feedback.gd")
const Magic = preload("res://tests/magic_checks.gd")


func run(root, checks) -> void:
	_particles(checks)
	_areas(root, checks)
	_cursor(root, checks)


func _particles(checks) -> void:
	var popup := Feedback.new()
	popup.add_text(Vector2(100, 100), "-7", 0)
	popup.add_text(Vector2(100, 100), "+20 реген.", 0)
	checks.check(popup.records().size() == 1 and popup.records()[0]["color"].r > popup.records()[0]["color"].g, "damage is red and regeneration cannot obscure the impact immediately")
	popup.advance(0.5)
	checks.check(popup.records().size() == 2 and popup.records()[1]["color"].g > popup.records()[1]["color"].r and popup.records()[0]["point"].distance_to(popup.records()[1]["point"]) >= 16, "regeneration appears later in green and apart from damage")
	for spell in range(Spell.COUNT):
		var reference: Array = []
		for fps in [30, 60, 144]:
			var feedback := Feedback.new()
			feedback.add_spell(spell, Vector2i(10, 12), 0)
			for frame in range(int(fps / 2.0)): feedback.advance(1.0 / fps)
			var particles: Array = Visuals.impact_particles(spell, Vector2i(10, 12), feedback.clock)
			checks.check(not particles.is_empty() and particles.size() <= 14, "bounded spell %d impact particles at %d FPS" % [spell, fps])
			if reference.is_empty(): reference = particles
			else: checks.check(particles == reference, "spell %d particles are independent of FPS" % spell)
			feedback.advance(1)
			checks.check(feedback.spell_impacts.is_empty() and Visuals.impact_particles(spell, Vector2i(10, 12), feedback.clock).is_empty(), "spell impact expires without another draw")
		var feedback := Feedback.new()
		feedback.add_spell(spell, Vector2i.ZERO, 0)
		feedback.clear()
		checks.check(feedback.spell_impacts.is_empty(), "reset clears spell %d presentation" % spell)


func _areas(root, checks) -> void:
	var pair: Array = Magic.new().fixture(root.world, root.metadata, root.table)
	var game = pair[0]
	var battle = pair[1]
	var caster = battle.unit(2000)
	var cell := Vector2i(21, 16)
	var before: Dictionary = battle.snapshot()
	var area: Dictionary = Spells.area_preview(battle, caster, Spell.FIREBALL, cell)
	var diamond: Array[Vector2i] = [cell + Vector2i.UP, cell + Vector2i.LEFT, cell, cell + Vector2i.RIGHT, cell + Vector2i.DOWN]
	checks.check(area["cells"] == diamond and area["possible"].is_empty(), "rank-one Fireball previews the exact five-cell diamond in hit order")
	checks.check(battle.snapshot() == before, "AOE hover preserves HP, mana, turns, commands and combat RNG")
	var enemy = battle.unit(1001)
	enemy.base_stats[Stat.MAX_HP] = 100000
	enemy.recalculate(root.table)
	enemy.stats[Stat.HP] = enemy.stats[Stat.MAX_HP]
	var hits: int = battle.events.filter(func(event): return event["event"] == "hit").size()
	Spells.impact(battle, caster, Spell.FIREBALL, cell)
	var new_hits: int = battle.events.filter(func(event): return event["event"] == "hit").size() - hits
	checks.check(new_hits == 3, "actual Fireball hits the three overlapping cells of a large enemy, preserving source repeated hits")
	caster.base_stats[Stat.DARK_AIR_MAGIC] = 10
	caster.recalculate(root.table)
	area = Spells.area_preview(battle, caster, Spell.LIGHTNING, cell)
	checks.check(area["cells"].size() == 9 and cell + Vector2i(0, 2) in area["cells"] and cell + Vector2i(1, 1) not in area["cells"], "Lightning previews the source Frost-school cross rather than a disk or its own school rank")
	var rng: Dictionary = battle.rng.snapshot()
	area = Spells.area_preview(battle, caster, Spell.FROST, cell)
	checks.check(area["cells"] == [cell, cell + Vector2i.RIGHT] and not area["possible"].is_empty(), "Frost separates the fixed two-cell strike from possible random pairs")
	checks.check(battle.rng.snapshot() == rng, "random Frost preview never samples its future combat RNG")
	game.hero.move_to(cell)
	area = Spells.area_preview(battle, caster, Spell.FROST, cell)
	checks.check(area["cells"].is_empty(), "Frost preview excludes a central pair blocked by an ally")
	area = Spells.area_preview(battle, caster, Spell.MIASMA, cell)
	checks.check(area["cells"].size() == 16 and area["cells"][0] == cell - Vector2i(2, 2) and area["cells"][-1] == cell + Vector2i(1, 1), "Miasma previews its exact asymmetric four-by-four source rectangle")
	checks.check(not area["allies"].is_empty() and area["caption"].contains("союзник"), "persistent damage warns about an allied unit inside its area")
	var hp: int = game.hero.stats[Stat.HP]
	Spells.impact(battle, caster, Spell.MIASMA, cell)
	battle._tick_hazards()
	checks.check(game.hero.stats[Stat.HP] < hp, "Miasma ally warning corresponds to actual periodic friendly damage")
	area = Spells.area_preview(battle, caster, Spell.FIREBALL, cell)
	checks.check(area["allies"].is_empty(), "direct Fireball retains its original enemy-only damage")
	var wall_cell := Vector2i(26, 20)
	area = Spells.area_preview(battle, caster, Spell.FIRE_WALL, wall_cell)
	Spells.impact(battle, caster, Spell.FIRE_WALL, wall_cell)
	var wall: Array = battle.hazards.filter(func(hazard): return hazard["spell"] == Spell.FIRE_WALL).map(func(hazard): return hazard["cell"])
	checks.check(area["cells"] == wall, "Fire Wall preview agrees with the actual placed strips")
	for single in [Spell.METEOR, Spell.FIRE_ARROW, Spell.SPARK, Spell.HEAL, Spell.PETRIFY]:
		checks.check(Spells.area_preview(battle, caster, single, cell).is_empty(), "single-target spell %d does not invent an AOE radius" % single)
	area = Spells.area_preview(battle, caster, Spell.MIASMA, Vector2i.ZERO)
	checks.check(area["cells"].all(func(point): return game.collision.contains(point)), "AOE overlay stays inside map bounds")


func _cursor(root, checks) -> void:
	root._demo_battle(true)
	root.battle_overlay.acknowledge()
	var caster = root.battle.unit(1001)
	for school in Ids.MAGIC_SCHOOLS: caster.base_stats[school] = 9
	caster.base_stats[Stat.MAX_MANA] = 1000
	caster.recalculate(root.table)
	caster.stats[Stat.MANA] = caster.stats[Stat.MAX_MANA]
	root.battle.select(caster.instance_id)
	root._choose_action("magic", -1)
	root._choose_action("spell", Spell.FIREBALL)
	var target: Vector2i = root.battle.unit(1004).cell
	var before: Dictionary = root.battle.snapshot()
	var state: Dictionary = root.cursors.resolve(root, root.view.cell_center(target), true)
	root.view.set_spell_preview(state)
	checks.check(state.get("cell") == target and not root.view.spell_preview.is_empty(), "live selected-spell cursor supplies its target to the AOE overlay")
	checks.check(root.battle.snapshot() == before, "live AOE cursor does not spend resources or mutate battle")
	root.view.set_spell_preview({"kind": "spell", "spell": Spell.FIREBALL, "cell": target, "blocked": true})
	checks.check(root.view.spell_preview.is_empty(), "invalid or unaffordable spell target clears the preview")
	root.view.set_spell_preview(root.cursors.resolve(root, root.view.cell_center(target), false))
	checks.check(root.view.spell_preview.is_empty(), "leaving the map clears the AOE preview")
	root._restart(false)
