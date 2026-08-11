extends SceneTree

const Generator := preload("res://generator.gd")
const Fidelity := preload("res://fidelity.gd")


func _initialize() -> void:
	var payload := ""
	for band in Fidelity.element_bands(Generator.build(42), 0.0):
		payload += "%s\t%s\n" % [band.beat_id, band.kind]
	var output_path := OS.get_environment("INVENTORY_OUT")
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		printerr("Cannot write inventory payload: %s" % output_path)
		quit(1)
		return
	output.store_string(payload)
	output.close()
	print(payload.trim_suffix("\n"))
	quit(0)
