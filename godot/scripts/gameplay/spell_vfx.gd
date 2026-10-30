extends RefCounted
## Presentation only: original sprites plus deterministic light, dust and runes.
const Ids = preload("res://scripts/gameplay/game_ids.gd")
const Spell = Ids.Spell
const Visuals = preload("res://scripts/gameplay/spell_presentation.gd")
var _light: Texture2D


func _glow(canvas: CanvasItem, point: Vector2, color: Color, extent: Vector2) -> void:
	if _light == null: _light = Visuals.radial_glow(Color.WHITE)
	canvas.draw_texture_rect(_light, Rect2((point - extent * 0.5).floor(), extent), false, color)


func _ring(canvas: CanvasItem, point: Vector2, radius: float, color: Color, squash: float = 0.4, rotation: float = 0, extent: float = TAU) -> void:
	var points := PackedVector2Array()
	for index in range(33):
		var angle: float = rotation + extent * index / 32.0
		points.append((point + Vector2(cos(angle), sin(angle) * squash) * radius).floor())
	canvas.draw_polyline(points, color, 1.0)


func _mote(canvas: CanvasItem, point: Vector2, color: Color, size: int = 1, cross: bool = false) -> void:
	canvas.draw_rect(Rect2(point.floor(), Vector2.ONE * size), color)
	if cross:
		canvas.draw_line(point.floor() - Vector2(2, 0), point.floor() + Vector2(2, 0), color)
		canvas.draw_line(point.floor() - Vector2(0, 2), point.floor() + Vector2(0, 2), color)


func draw_cast(canvas, spell: int, from: Vector2, to: Vector2, progress: float, elapsed: float, cell: Vector2i) -> void:
	var foot: Vector2 = to + Vector2(0, 12)
	var color: Color = Visuals.spell_color(spell)
	var pulse: float = 0.75 + sin(elapsed * 9) * 0.15
	match spell:
		Spell.SPARK:
			var point: Vector2 = from.lerp(to, progress)
			var direction: Vector2 = (to - from).normalized()
			var points := PackedVector2Array()
			for index in range(7):
				var offset: float = sin(index * 2.7 + floorf(elapsed / 0.062) * 1.8) * 3
				points.append((point - direction * (6 - index) * 4 + direction.orthogonal() * offset).floor())
			_glow(canvas, point, Color(0.25, 0.65, 1, 0.8), Vector2(38, 38))
			canvas.draw_polyline(points, Color(0.25, 0.55, 1, 0.7), 3)
			canvas.draw_polyline(points, Color("d8f7ff"), 1)
			var frame: int = Visuals.projectile_frame(direction)
			canvas.draw_texture_rect_region(canvas.textures[Ids.ImageId.SPARK_PROJECTILE], Rect2((point - Vector2(10, 10)).floor(), Vector2(20, 20)), Rect2(frame * 20, 0, 20, 20))
			for index in range(5): _mote(canvas, point - direction * (index * 5) + Vector2(0, sin(index + elapsed * 18) * 5), Color(0.6, 0.9, 1, 1.0 - index / 5.0), 1, index == 0)
		Spell.FIREBALL:
			var point: Vector2 = from.lerp(to, progress)
			_glow(canvas, point, Color(1, 0.4, 0.07, pulse), Vector2(52, 48))
			for index in range(8):
				var trail: Vector2 = from.lerp(to, maxf(0, progress - index * 0.025))
				_glow(canvas, trail, Color(1, 0.3, 0.05, (1.0 - index / 8.0) * 0.35), Vector2(22, 22))
				_mote(canvas, trail + Vector2(sin(index * 2 + elapsed * 15) * 6, -index), Color(1, 0.72, 0.2, 1.0 - index / 8.0), 2)
			canvas.draw_texture(canvas.textures[Ids.ImageId.FIREBALL], (point - Vector2(11, 16)).floor())
		Spell.HEAL:
			_glow(canvas, foot - Vector2(0, 16), Color(0.2, 1, 0.45, pulse * 0.4), Vector2(48, 56))
			_ring(canvas, foot, 12 + sin(elapsed * 6) * 2, Color(0.4, 1, 0.65, 0.75))
			for index in range(9):
				var age: float = fposmod(progress * 1.5 + index * 0.137, 1.0)
				var point: Vector2 = foot + Vector2(sin(index * 2.4 + age) * 14, 4 - age * 46)
				_mote(canvas, point, Color(0.5, 1, 0.7, sin(age * PI)), 1, true)
		Spell.SLOW:
			var center: Vector2 = foot - Vector2(0, 22)
			_glow(canvas, center, Color(0.5, 0.25, 0.9, 0.4), Vector2(44, 50))
			_ring(canvas, center, 17 - progress * 6, Color(0.75, 0.6, 1, 0.8), 1.0)
			for index in range(8):
				var angle: float = index * TAU / 8
				canvas.draw_line(center + Vector2.RIGHT.rotated(angle) * 10, center + Vector2.RIGHT.rotated(angle) * 13, color)
			canvas.draw_line(center, center + Vector2.RIGHT.rotated(-elapsed * 2) * 9, color, 1)
			canvas.draw_line(center, center + Vector2.RIGHT.rotated(-elapsed * 0.5 - PI / 2) * 6, Color("e6dcff"), 1)
			_ring(canvas, foot, 19 - progress * 10, Color(0.65, 0.4, 1, 0.7))
		Spell.HASTE:
			_glow(canvas, foot - Vector2(0, 15), Color(1, 0.75, 0.25, 0.35), Vector2(38, 52))
			for index in range(8):
				var age: float = fposmod(progress * 3 + index * 0.173, 1.0)
				var point: Vector2 = foot + Vector2(sin(index * 2.1) * 15, 8 - age * 52)
				canvas.draw_line(point, point + Vector2(3, -7), Color(1, 0.87, 0.5, sin(age * PI)), 1)
			for index in range(3): _ring(canvas, foot - Vector2(0, index * 10), 15, Color(1, 0.84, 0.4, 0.7), 0.35, elapsed * 10 + index * 2, PI * 0.8)
		Spell.VAMPIRISM:
			_glow(canvas, foot - Vector2(0, 20), Color(0.85, 0.03, 0.2, 0.45), Vector2(42, 52))
			for index in range(16):
				var age: float = index / 16.0
				var angle: float = age * TAU * 2 - elapsed * 6
				var point: Vector2 = foot + Vector2(cos(angle) * 13, -age * 40 + sin(angle) * 4)
				_mote(canvas, point, Color(1, 0.2 + age * 0.3, 0.35, 0.8), 2)
			_ring(canvas, foot, 13, Color(0.9, 0.15, 0.3, 0.8), 0.35, elapsed * 3, PI * 1.5)
			canvas.draw_texture_rect(canvas.textures[Ids.ImageId.BLOOD_DROP], Rect2(foot - Vector2(6, 37), Vector2(12, 20)), false, Color(1, 0.7, 0.75, 0.9))
		Spell.MIASMA:
			draw_miasma(canvas, cell, elapsed, 0.25 + progress * 0.65)
		Spell.FIRE_WALL:
			_glow(canvas, foot, Color(1, 0.4, 0.1, 0.45), Vector2(44, 26))
			for strip: Dictionary in Visuals.fire_wall_strips(cell, elapsed, canvas.textures[Ids.ImageId.FIRE_WALL].get_size()):
				var rect: Rect2 = strip["destination"]
				rect.position.y += (1.0 - progress) * 18
				canvas.draw_texture_rect_region(canvas.textures[Ids.ImageId.FIRE_WALL], rect, strip["source"], Color(1, 1, 1, progress))
		Spell.PETRIFY, Spell.STONE_SKIN:
			_draw_earth(canvas, foot, progress, elapsed, spell == Spell.STONE_SKIN)


func _draw_earth(canvas: CanvasItem, foot: Vector2, progress: float, elapsed: float, protecting: bool) -> void:
	var color := Color("d5bc86") if protecting else Color("b8b6b2")
	_glow(canvas, foot - Vector2(0, 15), Color(color, 0.3), Vector2(44, 50))
	_ring(canvas, foot, 16, Color(color, 0.75), 0.4, elapsed, TAU * 0.85)
	for index in range(8):
		var angle: float = index * TAU / 8 + elapsed * 1.5
		var point := (foot + Vector2(cos(angle) * 15, sin(angle) * 6 - fposmod(progress + index * 0.13, 1.0) * 34)).floor()
		var shard := PackedVector2Array([point + Vector2(-2, -3), point + Vector2(2, -4), point + Vector2(3, 2), point + Vector2(-1, 3)])
		canvas.draw_colored_polygon(shard, Color(color.darkened(0.35), 0.9))
		canvas.draw_line(point + Vector2(-2, -3), point + Vector2(2, -4), color)
	if protecting:
		var center: Vector2 = foot - Vector2(0, 24)
		var shield := PackedVector2Array([center + Vector2(-9, -9), center + Vector2(9, -9), center + Vector2(8, 3), center + Vector2(0, 11), center + Vector2(-8, 3), center + Vector2(-9, -9)])
		canvas.draw_colored_polygon(shield, Color(0.3, 0.28, 0.22, 0.35))
		canvas.draw_polyline(shield, Color(color, 0.85), 1)
		canvas.draw_line(center - Vector2(0, 5), center + Vector2(0, 5), color)
	else:
		var crack := PackedVector2Array([foot + Vector2(-3, -42), foot + Vector2(3, -32), foot + Vector2(-2, -23), foot + Vector2(4, -15), foot + Vector2(1, -5)])
		canvas.draw_polyline(crack, Color(0.85, 0.85, 0.8, progress * 0.8), 1)


func draw_miasma(canvas, cell: Vector2i, elapsed: float, opacity: float = 1) -> void:
	var center := Vector2(cell * 16)
	_glow(canvas, center - Vector2(0, 12), Color(0.35, 0.65, 0.1, 0.35 * opacity), Vector2(66, 48))
	for index in range(3):
		var sway := Vector2(sin(elapsed * 2.4 + index * 2) * 4, cos(elapsed * 1.9 + index) * 3)
		var extent := Vector2(34, 40) * (1.0 + sin(elapsed * 2 + index) * 0.1)
		var point: Vector2 = center + Vector2((index - 1) * 13, -15 - index % 2 * 9) + sway
		canvas.draw_texture_rect(canvas.textures[Ids.ImageId.MIASMA], Rect2((point - extent * 0.5).floor(), extent), false, Color(0.8, 1, 0.65, 0.5 * opacity))
	for index in range(8):
		var age: float = fposmod(elapsed * 0.5 + index * 0.153, 1.0)
		var point: Vector2 = center + Vector2(sin(index * 2.7) * 24 + sin(age * TAU) * 3, 6 - age * 38)
		_mote(canvas, point, Color(0.7, 0.95, 0.3, sin(age * PI) * opacity), 1)


func draw_impacts(canvas, feedback) -> void:
	for impact: Dictionary in feedback.spell_impacts:
		var spell: int = impact["spell"]
		var age: float = feedback.clock - float(impact["born"])
		if age < 0 or age >= Visuals.IMPACT_LIFETIME: continue
		var progress: float = age / Visuals.IMPACT_LIFETIME
		var color: Color = Visuals.spell_color(spell)
		var point := Vector2(Vector2i(impact["cell"]) * 16 + Vector2i(8, -4))
		_glow(canvas, point, Color(color, (1.0 - progress) * 0.5), Vector2(42, 42))
		if spell in [Spell.FIREBALL, Spell.METEOR, Spell.FROST, Spell.PETRIFY]:
			_ring(canvas, point + Vector2(0, 12), 5 + progress * (28 if spell == Spell.FIREBALL else 19), Color(color, (1.0 - progress) * 0.75))
		if spell == Spell.FIREBALL:
			for index in range(10):
				var angle: float = index * TAU / 10
				var ember: Vector2 = point + Vector2(cos(angle), sin(angle) * 0.7) * (5 + progress * 28) - Vector2(0, sin(progress * PI) * 9)
				canvas.draw_texture(canvas.textures[Ids.ImageId.FIRE_DEBRIS], (ember - Vector2(6, 6)).floor(), Color(1, 0.75, 0.45, (1.0 - progress) * 0.9))
		if spell == Spell.SPARK:
			for index in range(5):
				var direction := Vector2.RIGHT.rotated(index * TAU / 5 + 0.3)
				var ray := PackedVector2Array([point + direction * 3, point + direction * (10 + progress * 6) + direction.orthogonal() * 3, point + direction * (17 + progress * 8)])
				canvas.draw_polyline(ray, Color(color, 1.0 - progress), 1)
		for particle: Dictionary in Visuals.impact_particles(spell, impact["cell"], age):
			_mote(canvas, particle["point"], Color(color, particle["alpha"]), particle["size"], spell in [Spell.HEAL, Spell.SPARK, Spell.HASTE])


func draw_area(canvas: CanvasItem, area: Dictionary) -> void:
	if area.is_empty(): return
	for cell: Vector2i in area["possible"]:
		var rect := Rect2(Vector2(cell * 16) + Vector2.ONE, Vector2(14, 14))
		canvas.draw_rect(rect, Color(0.5, 0.75, 1, 0.1))
		for x in [rect.position.x, rect.end.x - 3]:
			for y in [rect.position.y, rect.end.y - 3]: canvas.draw_rect(Rect2(Vector2(x, y), Vector2(3, 3)), Color(0.65, 0.85, 1, 0.7), false, 1)
	for cell: Vector2i in area["cells"]:
		var color := Color("ffb95e") if cell not in area["allies"] else Color("ff6868")
		var rect := Rect2(Vector2(cell * 16) + Vector2.ONE, Vector2(14, 14))
		canvas.draw_rect(rect, Color(color, 0.24))
		canvas.draw_rect(rect, Color(color, 0.85), false, 1)
	var center := Vector2(Vector2i(area["target"]) * 16 + Vector2i(8, 8))
	canvas.draw_line(center - Vector2(4, 0), center + Vector2(4, 0), Color("fff1cb"), 1)
	canvas.draw_line(center - Vector2(0, 4), center + Vector2(0, 4), Color("fff1cb"), 1)
