extends SceneTree

# A guest wait that suspends: the vmcall returns at once, a host timer wakes the guest, and
# the default instruction budget is untouched because nothing polls.
const WAIT_NS := 50_000_000

func check(name: String, ok: bool, detail: String) -> int:
	print(("PASS " if ok else "FAIL ") + name + ("" if ok else " :: " + detail))
	return 0 if ok else 1

func _initialize() -> void:
	var failed := 0
	var sb = ClassDB.instantiate("Sandbox")
	sb.set("references_max", 20000)
	sb.set("unboxed_arguments", false)
	root.add_child(sb)
	sb.set("program", load("res://suspend.elf"))
	# Start once the loop is running, so the timer's first frame is an ordinary one.
	await process_frame
	await process_frame
	var started = sb.vmcall("suspend_start", WAIT_NS)
	failed += check("start returns at once", started == 0, "got %s" % [started])
	var early = sb.vmcall("suspend_elapsed")
	failed += check("not done when start returns", early == -1, "got %s" % [early])
	await create_timer(0.5).timeout
	var elapsed = sb.vmcall("suspend_elapsed")
	failed += check("done after the host timer fires", elapsed is int and elapsed >= 0, "got %s" % [elapsed])
	print("MEASURED guest-clock wait: %s us for a %s us request" % [elapsed, WAIT_NS / 1000])
	print("RESULT: ", failed, " falsified of 3")
	quit(failed)
