extends SceneTree

# Loads guest.elf into a Sandbox. Setting the program runs the guest's main(), which
# prints its own RESULT lines and registers add_numbers. Then call it from the host.
func _init() -> void:
	if not ClassDB.class_exists("Sandbox"):
		print("RESULT: FAIL the Sandbox class is not in this Godot build")
		quit(2)
		return
	var sb = ClassDB.instantiate("Sandbox")
	# The guest takes boxed Variant arguments (pointers), not native registers.
	sb.set("unboxed_arguments", false)
	sb.set("program", load("res://guest.elf"))
	var got = sb.vmcall("add_numbers", 3, 4)
	if got == 7:
		print("RESULT: vmcall add_numbers(3, 4) == 7")
	else:
		print("RESULT: FAIL vmcall add_numbers(3, 4) gave ", got)
	sb.free()
	quit(0 if got == 7 else 1)
