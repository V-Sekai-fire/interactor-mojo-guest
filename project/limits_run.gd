extends SceneTree

# Loads limits.elf into a Sandbox. Its main() runs the witness properties and prints.
func _init() -> void:
	var sb = ClassDB.instantiate("Sandbox")
	# Each string trial scopes one host variant, and the default allows 100.
	sb.set("references_max", 20000)
	# A timed wait polls the clock, and each poll is charged to the budget; 0 is no limit.
	sb.set("execution_timeout", 0)
	sb.set("program", load("res://limits.elf"))
	sb.free()
	quit(0)
