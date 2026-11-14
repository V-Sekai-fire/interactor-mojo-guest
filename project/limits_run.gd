extends SceneTree

# Loads limits.elf into a Sandbox. Its main() runs the witness properties and prints.
func _init() -> void:
	var sb = ClassDB.instantiate("Sandbox")
	# Each string trial scopes one host variant, and the default allows 100.
	sb.set("references_max", 20000)
	sb.set("program", load("res://limits.elf"))
	sb.free()
	quit(0)
