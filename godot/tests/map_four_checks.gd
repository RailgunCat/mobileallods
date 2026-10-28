extends RefCounted
const Session = preload("res://scripts/gameplay/game_session.gd")
const Story = preload("res://scripts/gameplay/campaign_runner.gd")
const Exploration = preload("res://scripts/gameplay/exploration_controller.gd")
const Saves = preload("res://scripts/gameplay/save_service.gd")
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const CampaignChecks = preload("res://tests/campaign_checks.gd")

func fixture(world, metadata, table, rewards):
	var game := Session.new()
	game.start(world, metadata, table, rewards)
	game.travel(3, 0)
	game.triggers[45] = Ids.TriggerState.ENABLED
	game.quests[9] = Ids.QuestState.ACTIVE
	return game

func approach(game) -> bool:
	# Walk across a real edge of the source conversation rectangle without
	# ignoring terrain or the hermit's collision footprint.
	var candidates: Array = []
	for x in range(528, 593, 4):
		candidates.append([Vector2(x, 388), Vector2(0, -4), Ids.Facing.UP])
		candidates.append([Vector2(x, 300), Vector2(0, 4), Ids.Facing.DOWN])
	for y in range(304, 385, 4):
		candidates.append([Vector2(524, y), Vector2(4, 0), Ids.Facing.RIGHT])
		candidates.append([Vector2(596, y), Vector2(-4, 0), Ids.Facing.LEFT])
	for candidate: Array in candidates:
		if not game.can_move_pixels(game.hero, candidate[0], candidate[2]) or not game.can_move_pixels(game.hero, candidate[0] + candidate[1], candidate[2]): continue
		game.hero.set_pixel_position(candidate[0])
		game.collision.occupy(game.hero.instance_id, game.hero.cell, game.hero.footprint)
		return game.move_pixels(game.hero, candidate[1])
	return false

func run(checks, world, metadata, table, rewards, data) -> void:
	var game = fixture(world, metadata, table, rewards)
	var story := Story.new()
	story.configure(game, world, data)
	checks.check(int(story.scripts[45][0]["operands"]["dialogue_id"]) == 39, "map four duplicate script ID resolves to the first record, like original m.void_d")
	checks.check(approach(game), "map four hermit trigger can be entered with checked pixel movement")
	story.check_triggers()
	story.advance(0.062)
	checks.check(story.modal.get("id", -1) == 39, "approaching the hermit opens his actual conversation instead of the abandoned-belongings dialogue")
	checks.check(CampaignChecks.new().settle(story), "map four hermit conversation finishes without a script fault")
	checks.check(game.spawn_states[17] == Ids.SpawnState.REMOVED and game.spawn_states[18] == Ids.SpawnState.VISIBLE and game.quests[9] == Ids.QuestState.COMPLETED, "hermit conversation hides him, reveals the guards and completes his quest")
	checks.check(game.triggers[45] == Ids.TriggerState.DISABLED, "completed hermit conversation remains one-shot")
	# Reproduce a manual save made after the old last-record lookup disabled
	# the trigger while leaving the hermit visible and his quest unfinished.
	game = fixture(world, metadata, table, rewards)
	story.configure(game, world, data)
	game.triggers[45] = Ids.TriggerState.DISABLED
	game.gold = 4567
	var flags_before: Dictionary = game.flags.duplicate(true)
	var movement := Exploration.new()
	movement.configure(game)
	var saves := Saves.new()
	saves.directory = "user://map-four-check-%d" % Time.get_ticks_usec()
	checks.check(saves.save_slot(0, game, story, movement), "broken map-four conversation state can be reproduced in a native save")
	var restored: Dictionary = saves.read_slot(0, world, metadata, table, rewards)
	checks.check(not restored.is_empty(), "map-four regression save loads successfully")
	if not restored.is_empty():
		game = restored["session"]
		story.configure(game, world, data)
		checks.check(game.triggers[45] == Ids.TriggerState.ENABLED and game.quests[9] == Ids.QuestState.ACTIVE, "loading an affected map-four save restores only the skipped conversation")
		flags_before["b"][45] = Ids.TriggerState.ENABLED
		checks.check(JSON.parse_string(JSON.stringify(game.flags)) == JSON.parse_string(JSON.stringify(flags_before)) and game.gold == 4567, "conversation repair preserves unrelated story flags, quest states and money")
		story.configure(game, world, data)
		checks.check(game.triggers[45] == Ids.TriggerState.ENABLED, "conversation repair is idempotent")
		checks.check(approach(game), "repaired save can approach the hermit normally")
		story.check_triggers()
		story.advance(0.062)
		checks.check(story.modal.get("id", -1) == 39 and CampaignChecks.new().settle(story), "repaired save resumes and finishes the original hermit conversation")
		story.configure(game, world, data)
		checks.check(game.triggers[45] == Ids.TriggerState.DISABLED, "repair never reopens a legitimately completed conversation")
		game.travel(0, 0)
		game.triggers[45] = Ids.TriggerState.DISABLED
		story.configure(game, world, data)
		checks.check(game.triggers[45] == Ids.TriggerState.DISABLED, "map-four recovery never changes the trigger on another map")
	for file in DirAccess.get_files_at(saves.directory): DirAccess.remove_absolute(saves.directory.path_join(file))
	DirAccess.remove_absolute(saves.directory)
