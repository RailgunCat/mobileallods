extends RefCounted
## Mutable item identity is separate from the table definition ID (ab).

var instance_id: int
var definition_id: int
var sockets: Array[int] = [] # Crystal definition IDs; -1 means empty.
var socket_instance_ids: Array[int] = [] # Inventory identities, retained while mounted.


func _init(id: int, definition: int) -> void:
	instance_id = id
	definition_id = definition
	if definition < 36:
		sockets.resize(definition % 3 + 1)
		sockets.fill(-1)
		socket_instance_ids.resize(sockets.size())
		socket_instance_ids.fill(-1)


func snapshot() -> Dictionary:
	return {"instance_id": instance_id, "definition_id": definition_id, "sockets": sockets.duplicate(), "socket_instance_ids": socket_instance_ids.duplicate()}
