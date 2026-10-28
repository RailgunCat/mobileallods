extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")

const Session = preload("res://scripts/gameplay/game_session.gd")
const Campaign = preload("res://scripts/gameplay/campaign_runner.gd")
const Exploration = preload("res://scripts/gameplay/exploration_controller.gd")
const Battle = preload("res://scripts/gameplay/battle_controller.gd")
const Combat = preload("res://tests/combat_checks.gd")


func settle(story, limit: int = 5000) -> bool:
	for i in range(limit):
		if not story.fault.is_empty(): return false
		if not story.busy(): return true
		if not story.modal.is_empty(): story.acknowledge()
		else: story.advance(0.062)
	return false


func drive(battle, limit: int = 3000) -> bool:
	# Original hint: defend with the front-line fighter while Li shoots.
	# This is a test player's tactic, not a change to enemy AI or unit balance.
	for i in range(limit):
		if battle.outcome != &"": return true
		if battle.can_input() and battle.selected_id >= 0:
			if battle.selected_id == battle.session.hero.instance_id and battle.session.party.size() > 1 and battle.session.party[1].unit_type == Ids.UnitKind.LI and not battle.session.party[1].dead:
				battle.defend()
			else: battle._enemy_action(battle.unit(battle.selected_id))
		battle.advance(0.062)
	return false


func run(checks, world: Dictionary, metadata: Dictionary, table: Dictionary, rewards: Dictionary, data: Dictionary) -> void:
	var game := Session.new()
	checks.check(game.start(world, metadata, table, rewards), "campaign starts original session")
	var story := Campaign.new()
	story.configure(game, world, data)
	story.check_triggers()
	checks.check(story.script_id == Ids.StoryScript.EXPLORATION_TUTORIAL, "entry picks source tutorial trigger")
	story.advance(0.062)
	var position: Vector2 = game.hero.position_pixels
	var ticks: int = story.ticks
	story.advance(100)
	checks.check(story.modal.get("kind") == "tutorial" and story.ticks == ticks and game.hero.position_pixels == position, "tutorial pauses simulation")
	checks.check(settle(story) and int(game.tutorial_seen[0]) == 1 and int(game.triggers[Ids.StoryScript.EXPLORATION_TUTORIAL]) == Ids.TriggerState.DISABLED, "tutorial acknowledged and disabled once")
	story.show_tutorial(0)
	checks.check(not story.busy(), "tutorial does not repeat")
	checks.check(story.start_script(Ids.StoryScript.ARRIVAL) and settle(story) and int(game.triggers[Ids.StoryScript.ARRIVAL]) == Ids.TriggerState.DISABLED, "original opening dialogue completes")
	story.start_script(Ids.StoryScript.QUAKE)
	story.advance(0.062)
	story.advance(0.062 * 48)
	checks.check(story.shaking and story.modal.is_empty(), "quake waits original 3000 milliseconds")
	checks.check(settle(story) and int(game.quests[Ids.Quest.WAY_HOME]) == Ids.QuestState.ACTIVE and int(game.triggers[Ids.StoryScript.RETURN_GATE]) == Ids.TriggerState.ENABLED, "quake starts path-home quest and closes return route")
	story.start_script(Ids.StoryScript.WOLF_CLEARING)
	checks.check(settle(story) and int(game.quests[Ids.Quest.WOLVES]) == Ids.QuestState.COMPLETED, "clearing marks wolf quest completed")
	story.start_script(Ids.StoryScript.HELP_HERMIT)
	checks.check(settle(story) and game.party.size() == 2 and game.party[1].instance_id == 1001 and int(game.spawn_states[6]) == 0, "source hermit joins and reveals bat before Li")
	var battle := Battle.new()
	battle.begin(game, [1003])
	checks.check(Combat.new().drive(battle) and battle.outcome == &"victory", "hero and original hermit win real bat combat")
	checks.check(battle.return_to_exploration(), "bat victory returns to exploration")
	story.after_battle(battle.participants)
	checks.check(story.script_id == Ids.StoryScript.BAT_DEFEATED and settle(story), "bat death hook executes original script 156")
	checks.check(game.party.size() == 1 and int(game.spawn_states[6]) == 2 and int(game.triggers[Ids.StoryScript.HERMIT_KEY]) == Ids.TriggerState.ENABLED, "hermit detaches and enables key conversation")
	story.start_script(Ids.StoryScript.HERMIT_KEY)
	checks.check(settle(story) and int(game.quests[Ids.Quest.HERMIT_KEY]) == Ids.QuestState.ACTIVE and int(game.triggers[Ids.StoryScript.MEET_LI]) == Ids.TriggerState.ENABLED, "hermit key quest unlocks Li meeting")
	story.start_script(Ids.StoryScript.MEET_LI)
	checks.check(settle(story) and game.party.size() == 2 and game.party[1].instance_id == 1002, "Li recruits original instance through dialogue and movement")
	checks.check(int(game.spawn_states[2]) == 2 and game.is_active(game.party[1]) and int(game.spawn_states[5]) == 2 and int(game.triggers[Ids.StoryScript.SOLO_TROLL_SOUTH]) == Ids.TriggerState.DISABLED and int(game.triggers[Ids.StoryScript.SOLO_TROLL_EAST]) == Ids.TriggerState.DISABLED, "recruitment hides hermit, retains party and removes solo troll warnings")
	story.start_script(Ids.StoryScript.TROLL_DEFEATED)
	checks.check(settle(story) and int(game.quests[Ids.Quest.LETTER]) == Ids.QuestState.COMPLETED and int(game.triggers[Ids.StoryScript.ENTER_DUNGEON]) == Ids.TriggerState.ENABLED, "troll dialogue completes letter quest and unlocks next location")
	game.quests[Ids.Quest.HERMIT_KEY] = Ids.QuestState.COMPLETED
	story.start_script(Ids.StoryScript.HERMIT_KEY)
	checks.check(settle(story) and int(game.quests[Ids.Quest.HERMIT_KEY]) == Ids.QuestState.COMPLETED, "completed quests cannot be reopened by script")
	story.scripts[200] = [{"opcode": Ids.ScriptOp.SET_SPAWN, "operands": {"spawn_flag": 2, "state": Ids.SpawnState.VISIBLE}, "offset": 1}]
	story.start_script(200)
	checks.check(settle(story) and int(game.spawn_states[2]) == 2, "permanently removed NPC spawn cannot be reactivated")
	story.scripts[201] = [{"opcode": 99, "args": [], "offset": 1}]
	story.start_script(201)
	story.advance(0.062)
	checks.check(not story.fault.is_empty() and story.pc == 0, "unsupported instruction produces diagnostic instead of skipping")
	story.configure(game, world, data)
	game.mode = &"exploration"
	story.start_script(Ids.StoryScript.ENTER_DUNGEON)
	var requested: Array = []
	story.travel_requested.connect(func(map_id: int, entry_id: int): requested.append([map_id, entry_id]))
	story.advance(0.062)
	checks.check(story.fault.is_empty() and game.mode == &"travel" and requested == [[-1, 0]], "source dungeon instruction requests travel with its entry")
