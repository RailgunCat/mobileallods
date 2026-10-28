extends RefCounted
## m.Z(): one safe passage per barrier; fifth draw is retained by the source.
const BOUNDS = [3, 2, 4, 3, 4]
const REGIONS = [
	[[68,128,384,144,432], [68,128,512,144,576], [68,128,640,144,704]],
	[[69,288,112,304,192], [69,272,528,304,592]],
	[[70,448,32,464,96], [70,448,192,464,256], [70,448,336,464,400], [70,448,560,464,624]],
	[[71,608,224,624,288], [71,608,368,624,432], [71,608,624,624,688]],
]

static func append_triggers(scene: Dictionary, choices: Array) -> void:
	for barrier in range(REGIONS.size()):
		for passage in range(REGIONS[barrier].size()):
			if passage != int(choices[barrier]): scene["triggers"].append(REGIONS[barrier][passage].duplicate())
