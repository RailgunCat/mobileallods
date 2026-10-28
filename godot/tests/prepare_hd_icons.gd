extends SceneTree
## Technical crops of the existing approved sheets; no artwork is regenerated.
func _initialize() -> void:
	var root: String = "res://data/hd/icons"
	DirAccess.make_dir_recursive_absolute(root)
	var source: String = "res://art/concepts/hd-icons-v1/"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source + "manifest.json"))
	var rectangles := {
		"02-dialogue-portraits-v1.png": [[0, 419, 834, 1254], [0, 414, 816, 1254]],
		"03-unit-portraits-v1.png": [[0, 328, 649, 973, 1298, 1619], [0, 319, 631, 971]],
		"04-spells-and-status-v1.png": [[0, 314, 627, 941, 1254], [0, 312, 624, 939, 1254]],
	}
	var exported: Dictionary = {"portraits": {}, "spells": {}, "sources": []}
	for asset: Dictionary in manifest["assets"]:
		var filename: String = asset["file"]
		if not rectangles.has(filename): continue
		var sheet := Image.load_from_file(source + filename)
		assert(sheet != null and sheet.get_width() == int(asset["width"]) and sheet.get_height() == int(asset["height"]))
		var axes: Array = rectangles[filename]
		for cell: Dictionary in asset["cells"]:
			var x: int = int(cell["column"]) - 1
			var y: int = int(cell["row"]) - 1
			var rect := Rect2i(int(axes[0][x]) + 8, int(axes[1][y]) + 8, int(axes[0][x + 1]) - int(axes[0][x]) - 16, int(axes[1][y + 1]) - int(axes[1][y]) - 16)
			var crop: Image = sheet.get_region(rect)
			var spell: bool = filename.begins_with("04-")
			var id: int = int(cell.get("source_frame", 15)) if spell else int(cell["source_image_id"])
			var category: String = "spells" if spell else "portraits"
			var target: String = "%s/%s-%03d.png" % [root, category, id]
			# Square spell buttons; portraits preserve the original canvas aspect ratio.
			var canvas := Vector2i(256, 256)
			if not spell:
				var original := Image.load_from_file("res://data/legacy/images/%03d.png" % id)
				assert(original != null)
				canvas = Vector2i(original.get_width() * 8, original.get_height() * 8)
			var ratio: float = minf(float(canvas.x) / crop.get_width(), float(canvas.y) / crop.get_height())
			crop.resize(maxi(1, roundi(crop.get_width() * ratio)), maxi(1, roundi(crop.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
			crop.convert(Image.FORMAT_RGBA8)
			var image := Image.create(canvas.x, canvas.y, false, Image.FORMAT_RGBA8)
			image.fill(Color.TRANSPARENT)
			image.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), (canvas - crop.get_size()) / 2)
			assert(image.save_png(target) == OK)
			exported[category][str(id)] = target
			exported["sources"].append({"file": filename, "sha256": asset["sha256"], "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "output": target})
	var file := FileAccess.open(root + "/manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(exported, "\t"))
	file.close()
	print("HD icons prepared: %d portraits, %d spells/status" % [exported["portraits"].size(), exported["spells"].size()])
	quit()
