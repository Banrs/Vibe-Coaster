extends SceneTree
## Headless architecture check: generate through the extension and print the
## numbers to compare against the CLI's.

func _initialize() -> void:
	var ride: Dictionary = RideGenerator.new().generate()
	print("samples: %d" % ride.positions.size())
	print("duration: %.2f s" % ride.duration)
	print("note: %s" % ride.note)
	print("stats: %s" % ride.stats)
	var ok: bool = ride.positions.size() > 1000 and is_finite(ride.duration) and ride.duration > 0.0
	quit(0 if ok else 1)
