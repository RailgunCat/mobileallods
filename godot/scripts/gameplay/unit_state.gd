extends RefCounted
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const StoryGroup = Ids.StoryGroup
const UnitKind = Ids.UnitKind
const Facing = Ids.Facing
const Stat = Ids.Stat

const Stats = preload("res://scripts/gameplay/unit_stats.gd")
const Item = preload("res://scripts/gameplay/item_instance.gd")

var instance_id: int
var unit_type: int
var story_group: int
var spawn_flag: int
var side_id: int
var footprint := Vector2i.ONE
var cell := Vector2i.ZERO # Top-left of footprint, not the sprite anchor.
var position_pixels := Vector2.ZERO
var facing: int = Facing.LEFT
var base_stats := PackedInt32Array()
var stats := PackedInt32Array()
var weapon: Item
var armor: Item
var collision_half_extents := Vector2i(10, 10)
var previous_position := Vector2.ZERO
var walking: bool = false
var animation_frame: int = 0
var _animation_facing: int = -1
var _frame_ticks_left: int = 0
var encounter_enabled: bool = false
var collision_enabled: bool = true
var story_marked: bool = false
var dead: bool = false
var attribute_points: int = 0
var skill_points: int = 0
var story_refs: Array[int] = [Ids.NO_STORY_HOOK, Ids.NO_STORY_HOOK, Ids.NO_STORY_HOOK]
var death_script: int:
	get: return story_refs[1] # Decoded legacy hook layout; callers use the named property.
var effects: Array[Dictionary] = []
var shattered: bool = false
var petrify_rounds: int = 0


func recalculate(table: Dictionary) -> void:
	stats = Stats.calculate(base_stats, table, weapon, armor, stats, effects)


func petrified() -> bool:
	return petrify_rounds > 0


func configure(definition: Dictionary, metadata: Dictionary, table: Dictionary) -> void:
	instance_id = int(definition["instance_id"])
	unit_type = int(definition["unit_type"])
	story_group = int(definition["story_group"])
	spawn_flag = int(definition["spawn_flag"])
	side_id = int(definition["side_id"])
	var extent: Array = metadata["unit_footprints"][unit_type]
	footprint = Vector2i(int(extent[0]), int(extent[1]))
	base_stats = Stats.row(table, Ids.AbilityRow.UNIT_BASE + unit_type)
	if unit_type in Ids.HERO_TYPES:
		var gear: Dictionary = metadata["starting_equipment"][unit_type]
		weapon = Item.new(instance_id * 10 + 1, int(gear["weapon"]))
		armor = Item.new(instance_id * 10 + 2, int(gear["armor"]))
	stats = Stats.calculate(base_stats, table, weapon, armor)
	var half: Array = metadata["exploration"]["unit_half_extents"][unit_type]
	collision_half_extents = Vector2i(int(half[0]), int(half[1]))
	animation_frame = int(metadata["exploration"]["units"][unit_type]["idle_frame"])


func set_pixel_position(point: Vector2) -> void:
	position_pixels = point
	# n.i(): Java truncation rather than floor matters for coordinates near 0.
	var corner: Vector2 = (point - Vector2(footprint) * 8) / 16.0
	cell = Vector2i(int(corner.x), int(corner.y))


func scale_for_location(level: int, table: Dictionary) -> void:
	if unit_type in Ids.HERO_TYPES: return
	base_stats[Stat.LEVEL] = level
	var bonus: int = 3 if level == 4 else 2
	var growth: int = level
	if level >= 9:
		bonus = 1
		growth -= 2
	for slot in range(Stat.ENDURANCE, Stat.LUCK + 1): base_stats[slot] += bonus * growth
	for slot in range(Stat.ATTACK, Stat.RESERVED + 1):
		if base_stats[slot] > 0: base_stats[slot] += growth
	stats = Stats.calculate(base_stats, table, weapon, armor)


func move_to(next: Vector2i) -> void:
	var delta := next - cell
	if delta.x != 0:
		facing = Facing.RIGHT if delta.x > 0 else Facing.LEFT
	elif delta.y != 0:
		facing = Facing.DOWN if delta.y > 0 else Facing.UP
	cell = next
	position_pixels = Vector2(cell) * 16 + Vector2(footprint) * 8


func render_record() -> Array:
	return render_at(position_pixels)


func render_at(point: Vector2) -> Array:
	return [instance_id, point.x, point.y, unit_type, story_group, spawn_flag, side_id, 0, 0, facing, animation_frame, walking, dead, shattered, petrified()]


func reset_interpolation() -> void:
	previous_position = position_pixels


func animate_tick(definition: Dictionary) -> void:
	var idle: int = int(definition["idle_frame"])
	var duration: int = int(definition["frame_ticks"][facing])
	if facing != _animation_facing:
		animation_frame = idle
		_animation_facing = facing
		_frame_ticks_left = duration
	if walking or unit_type == UnitKind.BAT:
		_frame_ticks_left -= 1
		if _frame_ticks_left <= 0:
			animation_frame = (animation_frame + 1) % definition["frame_columns"][facing].size()
			_frame_ticks_left = duration
	else:
		animation_frame = idle
		_frame_ticks_left = duration


func snapshot() -> Dictionary:
	return {"instance_id": instance_id, "unit_type": unit_type, "story_group": story_group, "story_refs": Array(story_refs), "spawn_flag": spawn_flag, "side_id": side_id, "cell": [cell.x, cell.y], "position_pixels": [position_pixels.x, position_pixels.y], "footprint": [footprint.x, footprint.y], "facing": facing, "walking": walking, "animation_frame": animation_frame, "encounter_enabled": encounter_enabled, "collision_enabled": collision_enabled, "story_marked": story_marked, "dead": dead, "shattered": shattered, "petrify_rounds": petrify_rounds, "effects": effects.duplicate(true), "attribute_points": attribute_points, "skill_points": skill_points, "base_stats": Array(base_stats), "stats": Array(stats), "stats_by_name": Stats.named(stats), "base_stats_by_name": Stats.named(base_stats), "weapon": weapon.snapshot() if weapon != null else {}, "armor": armor.snapshot() if armor != null else {}}
