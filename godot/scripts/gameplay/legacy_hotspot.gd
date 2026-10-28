extends RefCounted
## Logical input region. The screen dispatches mouse hits without extra canvas nodes.
signal pressed
var disabled: bool = false
var logical_rect: Rect2
var tooltip_text: String


func _gui_input(event: InputEvent) -> void:
	if not disabled and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
