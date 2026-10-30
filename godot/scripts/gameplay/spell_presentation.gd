extends RefCounted
## Recovered ag/h/w presentation, sampled without consuming simulation RNG.
const STEP: float = 0.062
const METEOR_FALL_TICKS: int = 14 # First n with n * (n + 1) > 190.
const DEBRIS_LIFETIME: float = 2.0
const Spells = preload("res://scripts/gameplay/spell_rules.gd")
const Spell = preload("res://scripts/gameplay/game_ids.gd").Spell
const IMPACT_LIFETIME: float = 12 * STEP


static func _hash(value: int) -> int:
	return (value * 1103515245 + 12345) & 0x7fffffff


static func meteor_position(cell: Vector2i, clock: float) -> Vector2:
	var tick: int = clampi(int(clock), 0, METEOR_FALL_TICKS - 1)
	var fraction: float = clampf(clock - tick, 0, 1)
	var descent: float = lerpf(tick * (tick + 1), (tick + 1) * (tick + 2), fraction)
	return (Vector2(cell * 16 + Vector2i(8, 8)) + Vector2(-13, -40 - 190 + descent)).floor()


static func meteor_shards(cell: Vector2i, age: float, seed_value: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	if age < 0 or age >= DEBRIS_LIFETIME: return result
	var ticks: int = int((age + 0.000000001) / STEP)
	var origin := Vector2(cell * 16 + Vector2i(8, -12))
	for index in range(10):
		var seed: int = _hash(seed_value + index * 997)
		var angle: float = deg_to_rad(seed % 360)
		var velocity := Vector2(cos(angle), sin(angle)) * 5
		var vertical_speed: int = -5 - _hash(seed) % 5
		var lift: int = 0
		var acceleration: int = 5
		var resting_tick: int = -1
		var ground := origin
		for tick in range(ticks):
			ground += velocity
			lift += vertical_speed
			vertical_speed += acceleration
			if acceleration != 0 and lift >= 0:
				lift = 0
				vertical_speed = int(-vertical_speed * 0.35)
				if vertical_speed >= -3:
					vertical_speed = 0
					acceleration = 0
					velocity = Vector2.ZERO
					resting_tick = tick
		if resting_tick >= 0 and (ticks - resting_tick) * STEP >= 1.0: continue
		result.append((ground + Vector2(0, lift)).floor())
	return result


static func projectile_frame(direction: Vector2) -> int:
	if absf(direction.x) >= absf(direction.y) * 3: return 0
	if absf(direction.y) >= absf(direction.x) * 3: return 1
	return 2 if direction.x * direction.y < 0 else 3


static func fire_glow() -> Texture2D:
	# m.t(): 40x40 ARGB4444 radial orange glow (0xe72), with stepped alpha.
	return radial_glow(Color(14.0 / 15, 7.0 / 15, 2.0 / 15))

static func fire_wall_strips(cell: Vector2i, clock: float, source_size: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tick: int = int((clock + 0.000000001) / STEP)
	var base := Vector2(cell * 16 + Vector2i(8, 12))
	for index in range(8):
		var phase: float = tick * 0.65 + index * 0.9 + cell.x * 0.7 + cell.y
		var height: float = 24 + roundf(sin(phase) * 3)
		var sway: float = roundf(sin(phase * 0.8) * 1.5)
		result.append({"source": Rect2(source_size.x * index / 8.0, 0, source_size.x / 8.0, source_size.y), "destination": Rect2(base.x - 12 + index * 3 + sway, base.y - height, 4, height)})
	return result

static func fire_wall_sparks(cell: Vector2i, clock: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tick: int = int((clock + 0.000000001) / STEP)
	var origin := Vector2(cell * 16 + Vector2i(8, 8))
	for index in range(7):
		var seed: int = _hash(cell.x * 173 + cell.y * 317 + index * 997)
		var age: float = float((tick + seed % 19) % 19) / 19.0
		result.append({"point": (origin + Vector2(seed % 23 - 11 + sin(age * TAU + index) * 2, 3 - age * 34)).floor(), "alpha": 1.0 - age, "size": 1 + seed % 2})
	return result


static func ice_glow() -> Texture2D:
	return radial_glow(Color(0.25, 0.6, 1.0, 0.75))


static func radial_glow(color: Color) -> Texture2D:
	var pixels := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	for y in range(40):
		for x in range(40):
			var radius: int = Spells.integer_root((x - 20) ** 2 + (y - 20) ** 2)
			if radius > 20: continue
			var alpha: int = 15 - int(15 * radius / 20.0)
			pixels.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * alpha / 15.0))
	return ImageTexture.create_from_image(pixels)


static func fire_sparks(from: Vector2, to: Vector2, clock: float, flight_ticks: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var now: int = int(clock)
	for emission in range(maxi(0, now - 8), mini(now, flight_ticks) + 1):
		var origin: Vector2 = from.lerp(to, clampf(float(emission) / flight_ticks, 0, 1))
		for index in range(10):
			var seed: int = _hash(emission * 65537 + index * 997 + int(from.x) * 173 + int(to.y) * 317)
			var lifetime: int = 3 + seed % 7
			var age: int = now - emission
			if age >= lifetime: continue
			var offset := Vector2(_hash(seed) % 20 - 10, _hash(seed + 1) % 20 - 10)
			var drift := Vector2(_hash(seed + 2) % 30 - 15, _hash(seed + 3) % 30 - 15) * age / 100.0
			result.append({"point": (origin + offset + drift).floor(), "size": 1 + seed % 2, "alpha": 1.0 - float(age) / lifetime})
	return result


static func spell_color(spell: int) -> Color:
	match spell:
		Spell.HEAL: return Color("65ef9b")
		Spell.LIGHTNING, Spell.SPARK: return Color("85d7ff")
		Spell.FROST: return Color("a0dfff")
		Spell.SLOW: return Color("b295ee")
		Spell.VAMPIRISM: return Color("ec4770")
		Spell.MIASMA: return Color("93c952")
		Spell.PETRIFY, Spell.STONE_SKIN: return Color("c6b594")
		Spell.HASTE, Spell.BLESS: return Color("ffe6a0")
		_: return Color("ffad4c")


static func impact_particles(spell: int, cell: Vector2i, age: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if age < 0 or age + 0.000000001 >= IMPACT_LIFETIME: return result
	var tick: int = int((age + 0.000000001) / STEP)
	var progress: float = tick / 12.0
	var center := Vector2(cell * 16 + Vector2i(8, -4))
	var rising: bool = spell in [Spell.HEAL, Spell.VAMPIRISM, Spell.HASTE, Spell.BLESS, Spell.STONE_SKIN]
	for index in range(14 if spell == Spell.FIREBALL else 9):
		var seed: int = _hash(cell.x * 173 + cell.y * 317 + spell * 65537 + index * 997)
		var angle: float = deg_to_rad(seed % 360)
		var radius: float = (6 + seed % 15) * progress
		var offset := Vector2(cos(angle) * radius, sin(angle) * radius * 0.65)
		if rising: offset = Vector2(seed % 25 - 12, 10 - progress * (20 + seed % 16))
		result.append({"point": (center + offset).floor(), "alpha": 1.0 - progress, "size": 1 + seed % 2})
	return result
