extends SceneTree

# Reads every clock from the guest, compares it with the same call made by the host, and then
# stalls the main thread to show which clocks follow the loop and which follow the device.
const NAMES := [
	"Time.get_ticks_usec", "Engine.get_physics_frames", "Engine.get_process_frames",
	"Engine.get_frames_drawn", "Engine.get_physics_ticks_per_second", "Engine.get_time_scale",
	"AudioServer.get_mix_rate", "AudioServer.get_time_since_last_mix",
	"AudioServer.get_time_to_next_mix", "AudioServer.get_output_latency",
]

var failed := 0

func check(name: String, ok: bool, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if ok else " :: " + detail))
	if not ok:
		failed += 1

func host(i: int) -> float:
	match i:
		0: return float(Time.get_ticks_usec())
		1: return float(Engine.get_physics_frames())
		2: return float(Engine.get_process_frames())
		3: return float(Engine.get_frames_drawn())
		4: return float(Engine.physics_ticks_per_second)
		5: return Engine.time_scale
		6: return AudioServer.get_mix_rate()
		7: return AudioServer.get_time_since_last_mix()
		8: return AudioServer.get_time_to_next_mix()
		_: return AudioServer.get_output_latency()

func _initialize() -> void:
	var sb = ClassDB.instantiate("Sandbox")
	sb.set("unboxed_arguments", false)
	root.add_child(sb)
	sb.set("program", load("res://guest.elf"))
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 48000.0
	gen.buffer_length = 1.0
	var player := AudioStreamPlayer.new()
	player.stream = gen
	player.volume_db = -80.0
	root.add_child(player)
	await process_frame
	player.play()
	await process_frame
	var pb: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var capacity := pb.get_frames_available()
	var pushed := 0
	for i in 20:
		var n := pb.get_frames_available()
		var buf := PackedVector2Array()
		buf.resize(n)
		pb.push_buffer(buf)
		pushed += n
		await process_frame

	print("-- access: each clock read by the guest, then by the host in the same frame")
	for i in NAMES.size():
		var g = sb.vmcall("read_clock", i)
		var h := host(i)
		var ok: bool = g is float
		print("%s %-38s guest=%s host=%s" % ["READ " if ok else "DENIED", NAMES[i], g, h])
		check("guest reads " + NAMES[i], ok, "got %s" % [g])
		# Counters and constants cannot change inside one frame, so the two reads must be equal.
		if i in [1, 2, 3, 4, 5, 6, 9]:
			check("guest equals host for " + NAMES[i], ok and g == h, "guest %s host %s" % [g, h])
	var obj_val = sb.vmcall("read_object", pb)
	print("%s %-38s guest=%s host=%s" % ["READ " if obj_val is float else "DENIED", "AudioStreamGeneratorPlayback.get_frames_available", obj_val, pb.get_frames_available()])

	print("-- stall: the main thread sleeps 300 ms inside one frame")
	var before := {}
	for i in [0, 1, 2, 3, 7]:
		before[i] = sb.vmcall("read_clock", i)
	var avail_before = sb.vmcall("read_object", pb)
	OS.delay_msec(300)
	print("%-38s %s" % ["clock", "guest-read change over the stall"])
	for i in [0, 1, 2, 3, 7]:
		var after = sb.vmcall("read_clock", i)
		print("%-38s %s" % [NAMES[i], after - before[i]])
	var avail_after = sb.vmcall("read_object", pb)
	var after_ticks = sb.vmcall("read_clock", 0)
	check("wall clock followed the 300 ms stall", after_ticks - before[0] >= 300000.0, "got %s" % [after_ticks - before[0]])
	for i in [1, 2, 3]:
		check("%s did not move in the stall" % NAMES[i], sb.vmcall("read_clock", i) == before[i], "moved")
	check("audio device kept consuming through the stall", avail_after - avail_before > 0, "got %s" % [avail_after - avail_before])
	print("RESULT: ", failed, " falsified")
	print("%-38s %s frames (generator buffer drained = audio device advanced %.1f ms)" % ["generator frames consumed", avail_after - avail_before, (avail_after - avail_before) / 48.0])
	quit(failed)
