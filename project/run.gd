extends SceneTree

# Loads guest.elf into a Sandbox. Setting the program runs the guest's main(),
# which prints its own RESULT line; test/run_godot.sh judges by that line.
func _init() -> void:
	if not ClassDB.class_exists("Sandbox"):
		print("RESULT: FAIL the Sandbox class is not in this Godot build")
		quit(2)
		return
	var sb = ClassDB.instantiate("Sandbox")
	sb.set("program", load("res://guest.elf"))
	sb.free()
	quit(0)
