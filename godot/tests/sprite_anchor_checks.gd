extends SceneTree
## GPU regression: compare actual blits with Java's whole-sheet mirror + clip.
## Run without --headless; the dummy renderer cannot validate pixel placement.

class Probe:
	extends "res://scripts/legacy_map_view.gd"
	var record: Array = []
	func _draw() -> void:
		if not record.is_empty(): _draw_unit(record)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(192, 192)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var probe := Probe.new()
	viewport.add_child(probe)
	probe.size = Vector2(192, 192)
	var graphics: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/legacy/graphics.json"))
	probe.configure({}, graphics)
	var failures: int = 0
	var cases: int = 0
	for type in [0, 1]:
		var definition: Dictionary = graphics["units"][type]
		for direction in range(8):
			for frame in range(definition["frame_columns"][direction].size()):
				probe.record = [1, 96, 128, type, 0, 0, 0, 0, 0, direction, frame, true, false]
				probe.queue_redraw()
				await process_frame
				await RenderingServer.frame_post_draw
				var actual: Image = viewport.get_texture().get_image()
				var pose: Dictionary = probe.sprite_pose(probe.record)
				var sheet: Image = probe.textures[pose["image"]].get_image()
				sheet.convert(Image.FORMAT_RGBA8)
				if direction in [1, 5]: sheet.flip_x()
				var expected := Image.create(192, 192, false, Image.FORMAT_RGBA8)
				expected.fill(Color.TRANSPARENT)
				var frame_size := Vector2i(pose["frame_size"])
				expected.blit_rect(sheet, Rect2i(Vector2i(int(pose["column"]), int(pose["row"])) * frame_size, frame_size), Vector2i(96, 128) - Vector2i(pose["origin"]))
				var different: int = 0
				for y in range(192):
					for x in range(192):
						var a: Color = actual.get_pixel(x, y)
						var e: Color = expected.get_pixel(x, y)
						if absf(a.a - e.a) > 0.01 or (e.a > 0 and (absf(a.r - e.r) + absf(a.g - e.g) + absf(a.b - e.b)) > 0.03): different += 1
				cases += 1
				if different > 0:
					failures += 1
					if failures <= 3: print("FAIL sprite anchor: type=%d direction=%d frame=%d mismatched pixels=%d" % [type, direction, frame, different])
					if failures == 1:
						var folder: String = ProjectSettings.globalize_path("res://../build")
						DirAccess.make_dir_recursive_absolute(folder)
						actual.save_png(folder.path_join("sprite-anchor-actual.png"))
						expected.save_png(folder.path_join("sprite-anchor-expected.png"))
	print("Sprite anchors: %d cases, %d failures" % [cases, failures])
	quit(0 if failures == 0 else 1)
