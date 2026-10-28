extends SceneTree
## Render a neutral field to measure visible scanlines and RGB phosphors.
## Run with a GPU; the headless renderer cannot verify a screen shader.
const CRT = preload("res://scripts/gameplay/crt_filter.gd")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func frame() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _run() -> void:
	var field := ColorRect.new()
	field.color = Color(0.5, 0.5, 0.5)
	field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(field)
	var crt := CRT.new()
	root.add_child(crt)
	for dimensions: Vector2i in [Vector2i(960, 600), Vector2i(1280, 800), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		root.size = dimensions
		crt.apply(false)
		var plain: Image = await frame()
		crt.apply(true)
		var filtered: Image = await frame()
		var center: Vector2i = filtered.get_size() / 2
		var low: float = 1.0
		var high: float = 0.0
		var chroma: float = 0.0
		for y in range(center.y - 12, center.y + 12):
			var row: float = 0.0
			for x in range(center.x - 30, center.x + 30):
				var color: Color = filtered.get_pixel(x, y)
				row += (color.r + color.g + color.b) / 3.0
				chroma = maxf(chroma, maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b)))
			row /= 60.0
			low = minf(low, row)
			high = maxf(high, row)
		check(high - low > 0.10, "CRT scanlines must have visible contrast at " + str(dimensions))
		check(chroma > 0.10, "CRT phosphor mask must have visible color separation at " + str(dimensions))
		crt.apply(false)
		var restored: Image = await frame()
		check(restored.get_data() == plain.get_data(), "Disabling CRT must restore the unprocessed image at " + str(dimensions))
		print("CRT ", dimensions, ": scanline contrast=", snappedf(high - low, 0.001), ", phosphor separation=", snappedf(chroma, 0.001))
	crt.queue_free()
	field.queue_free()
	await process_frame
	print("CRT render: 12 checks, ", failures, " failures")
	quit(1 if failures else 0)
