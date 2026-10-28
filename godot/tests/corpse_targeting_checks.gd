extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Unit = preload("res://scripts/gameplay/unit_state.gd")
const Stat = Ids.Stat

func run(root, checks) -> void:
	root._demo_battle()
	root.battle_overlay.acknowledge()
	root.battle.enemy_policy = &"defend"
	var body = root.battle.unit(1004)
	var hero = root.session.hero
	var cell: Vector2i = hero.cell + Vector2i.UP * 2
	root.session.collision.remove(body.instance_id)
	body.move_to(cell)
	body.reset_interpolation()
	root.session.collision.occupy(body.instance_id, cell, body.footprint)
	# An L-shaped one-cell corridor reproduces targeting by a cleared corpse
	# at a corner. The second hostile keeps combat active after the body clears.
	for y in range(cell.y - 1, hero.cell.y + 2):
		for x in range(cell.x - 1, cell.x + 5):
			root.session.collision.terrain[y * root.session.collision.width + x] = 1
	for open_cell: Vector2i in [hero.cell, hero.cell + Vector2i.UP, cell, cell + Vector2i.RIGHT, cell + Vector2i.RIGHT * 2, cell + Vector2i.RIGHT * 3]:
		root.session.collision.terrain[open_cell.y * root.session.collision.width + open_cell.x] = 0
	var enemy := Unit.new()
	enemy.configure({"instance_id": 9001, "unit_type": Ids.UnitKind.SQUIRREL, "story_group": Ids.StoryGroup.HOSTILES, "spawn_flag": body.spawn_flag, "side_id": Ids.Side.HOSTILE}, root.metadata, root.table)
	enemy.encounter_enabled = true
	enemy.move_to(cell + Vector2i.RIGHT * 3)
	enemy.reset_interpolation()
	root.session.units.append(enemy)
	root.battle.participants.append(enemy.instance_id)
	root.battle.state[enemy.instance_id] = root.battle.state[body.instance_id].duplicate(true)
	root.session.collision.occupy(enemy.instance_id, enemy.cell, enemy.footprint)
	body.dead = true
	body.stats[Stat.HP] = 0
	root.battle.state[body.instance_id]["ended"] = true
	root._refresh_battle()
	checks.check(not root.session.collision.can_stand(cell, hero.footprint, hero.instance_id), "intact corpse retains the original blocking behavior")
	root._select_battle_cell(cell)
	checks.check(root.attack_target_id == body.instance_id and not root.attack_button.disabled, "clicking an intact hostile corpse selects a valid clearing attack")
	root._select_battle_cell(cell)
	checks.check(root.battle.busy(), "repeat click orders the physical attack on the corpse")
	for tick in range(250):
		if not root.battle.busy(): break
		root._process(0.062)
	checks.check(body.shattered and not root.session.collision.units.has(body.instance_id), "physical hit destroys the corpse and frees collision")
	# Give the same party member a fresh action to isolate click targeting
	# from the normal rule that an attack finishes that member's action.
	root.battle.state[hero.instance_id]["ended"] = false
	hero.stats[Stat.ACTION_POINTS] = hero.stats[Stat.MAX_ACTION_POINTS]
	root.battle.select(hero.instance_id)
	root._refresh_battle()
	root._select_battle_cell(cell)
	checks.check(root.selected == cell and root.attack_target_id == -1 and not root.route.is_empty(), "cleared corpse cell accepts a movement click at the corridor corner")
	# A living enemy can later enter that old footprint. The removed body
	# must never consume its clicks, regardless of participant iteration order.
	root.session.collision.remove(enemy.instance_id)
	enemy.move_to(cell)
	enemy.reset_interpolation()
	root.session.collision.occupy(enemy.instance_id, enemy.cell, enemy.footprint)
	root._select_battle_cell(cell)
	checks.check(root.attack_target_id == enemy.instance_id and not root.attack_button.disabled, "living enemy on a destroyed corpse's old cell can be attacked without repositioning")
	root._select_battle_cell(cell)
	checks.check(root.battle.busy(), "repeat click attacks the live enemy at the cleared corner")
	root._restart(false)
