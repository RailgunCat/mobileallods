extends CanvasLayer
## Aperture-grille CRT with static beams, phosphor stripes and halation.
## Screen coordinates remain unchanged for accurate mouse targeting.
const SHADER = preload("res://shaders/crt.gdshader")
var overlay: ColorRect

func _ready() -> void:
	layer = 100
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = SHADER
	overlay.material = shader_material
	add_child(overlay)
	overlay.hide()

func apply(enabled: bool) -> void:
	if overlay != null: overlay.visible = enabled
