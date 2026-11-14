extends SceneTree

# Limits that only a Sandbox host can show. Same red/green rule as tests/limits.mojo,
# but these are GDScript checks, not witness properties: a witness property runs in the
# guest and cannot choose how the host passes its arguments.
var failed := 0

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS ", name)
	else:
		failed += 1
		print("FAIL ", name, " :: ", detail)

func make_sandbox(unboxed: bool):
	var sb = ClassDB.instantiate("Sandbox")
	sb.set("unboxed_arguments", unboxed)
	sb.set("program", load("res://guest.elf"))
	return sb

func _init() -> void:
	var sb = make_sandbox(false)
	var got = sb.vmcall("add_numbers", 3, 4)
	check("boxed vmcall (control)", got == 7, "got %s" % [got])
	var again = [sb.vmcall("add_numbers", 10, 20), sb.vmcall("add_numbers", -5, 5), sb.vmcall("add_numbers", 1 << 40, 1)]
	check("repeated vmcall", again == [30, 0, (1 << 40) + 1], "got %s" % [again])
	sb.free()
	var ub = make_sandbox(true)
	var u = ub.vmcall("add_numbers", 3, 4)
	check("unboxed vmcall", u == 7, "got %s" % [u])
	ub.free()
	print("RESULT: ", failed, " falsified of 3")
	quit(1 if failed > 0 else 0)
