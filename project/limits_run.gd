extends SceneTree

# Loads limits.elf into a Sandbox. Its main() runs the witness properties and prints.
func _init() -> void:
	var sb = ClassDB.instantiate("Sandbox")
	sb.set("program", load("res://limits.elf"))
	sb.free()
	quit(0)
