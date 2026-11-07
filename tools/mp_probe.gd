## Two-PC smoke test on one machine (headless):
##   godot --headless --path . --script res://tools/mp_probe.gd -- host &
##   godot --headless --path . --script res://tools/mp_probe.gd -- client
## (Timings allow for the client starting ~4 s after the host and the maps taking a while to load.)
## Prints what each side sees (puppets, remote players, bait, a grab, the host ending the night).
extends SceneTree
var role:= ""
var t:= 0.0
var phase:= 0
var net
var gs
func _initialize():
	role = OS.get_cmdline_user_args()[0]
	gs = root.get_node("GameState")
	gs.saving_enabled = false
	gs.reset()
	gs.current_map = "woods"
	net = root.get_node("Net")
	net.my_name = "HostIan" if role == "host" else "ClientAlex"
	change_scene_to_file("res://main.tscn")
var fr:= 0
func _process(d):
	t += d
	fr += 1
	var m = current_scene
	if role == "host" and phase == 0 and t > 0.5 and not net.online():
		net.host_game(24690)
	if role == "host" and t > 12.0 and t < 12.02:
		Input.action_press("move_forward")
	if role == "host" and t > 13.0 and t < 13.02:
		Input.action_release("move_forward")
	if role == "client" and m != null and m.get("_net") != null and t > 16.5 and not has_meta("faced"):
		set_meta("faced", true)
		var ns = m.get("_net")
		for id in ns.remotes:
			m.get("_player").face_point(ns.remotes[id].global_position + Vector3(0, 0.3, 0), 0.0)
	if role == "client" and t > 17.5 and not has_meta("shot") and OS.get_environment("SHOT") != "":
		set_meta("shot", true)
		print("CLIENT shot at t=", t, " remotes=", m.get("_net").remotes.keys())
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT"))
	if role == "client" and phase == 0 and t > 4.0:
		phase = 1
		net.join_game("127.0.0.1", 24690)
	if m == null or m.get("_player") == null:
		return false
	var p = m.get("_player")
	if role == "client" and phase == 1 and t > 14.0 and OS.get_environment("SHOT") == "":
		phase = 2
		var cs = m.get("_cryptids")
		print("CLIENT puppets=", cs.size(), " puppet0=", cs[0].puppet if cs.size() > 0 else "-", " remotes=", m.get("_net").remotes.keys(), " players=", net.players)
		if cs.size() > 0:
			print("CLIENT c0 ", cs[0].species_id, " at ", cs[0].global_position.snapped(Vector3.ONE * 0.1), " state=", cs[0].state)
			cs[0].hear_noise(cs[0].global_position + Vector3(12, 0, 0), 50.0)
		m.get("_net").place_item("bait", Transform3D(Basis.IDENTITY, p.global_position + Vector3(0, -0.7, -2)))
		Input.action_press("move_forward")
	if role == "client" and phase == 2 and t > 15.0:
		phase = 3
		Input.action_release("move_forward")
		var cs = m.get("_cryptids")
		print("CLIENT after noise: c0 state=", cs[0].state if cs.size() > 0 else -1, " bait_here=", get_nodes_in_group("bait").size(), " my pos=", p.global_position.snapped(Vector3.ONE * 0.1))
	if t > 15.0 and not has_meta("voiced") and m.get("_net") != null:
		set_meta("voiced", true)
		var ML = load("res://scripts/mic_listener.gd")
		var sine:= PackedFloat32Array()
		for i in 320:
			sine.append(sin(i * 0.2) * 0.5)
		for k in 10:
			m.get("_net").send_voice(ML.encode(sine))
	if role == "client" and t > 15.2 and not has_meta("props") and m.get("_net") != null:
		set_meta("props", true)
		gs.tripods = 1
		m.get("_player").select_item("tripod")
		m.get("_player").use_item()
		m.call("_summon_ufo")
	if role == "host" and t > 24.0 and not has_meta("props_report"):
		set_meta("props_report", true)
		print("HOST sees client tripods=", m.get("_net")._ghost_tripods.size(), " client ufos=", m.get("_net")._ghost_ufos.size())
	if t > 24.0 and not has_meta("voice_report") and m.get("_net") != null:
		set_meta("voice_report", true)
		for id in m.get("_net").remotes:
			print(role.to_upper(), " heard ", m.get("_net").remotes[id].voice_samples, " voice samples from ", id)
	if role == "host" and phase == 0 and t > 23.0:
		phase = 1
		var cs = m.get("_cryptids")
		var ns = m.get("_net")
		print("HOST cryptids=", cs.size(), " remotes=", ns.remotes.keys(), " ready=", ns._ready_peers.keys())
		if cs.size() > 0:
			print("HOST c0 ", cs[0].species_id, " at ", cs[0].global_position.snapped(Vector3.ONE * 0.1), " state=", cs[0].state, " target=", ns.target_id(cs[0]))
		for id in ns.remotes:
			print("HOST sees remote ", id, " at ", ns.remotes[id].global_position.snapped(Vector3.ONE * 0.1), " name=", net.name_of(id))
		print("HOST bait=", get_nodes_in_group("bait").size())
	if role == "host" and phase == 0 and t > 22.0 and not has_meta("grabbed"):
		set_meta("grabbed", true)
		var cs = m.get("_cryptids")
		var ns = m.get("_net")
		for id in ns.remotes:
			cs[0].player_ref = ns.remotes[id]
			cs[0].state = 3
			m.call("_on_caught", cs[0])
	if role == "client" and phase == 2 and t > 14.5 and gs.unsold_photos.is_empty():
		gs.unsold_photos = [{"value": 77, "species": ["cornicorn"]}]
	if role == "client" and t > 21.0 and not has_meta("grab_report"):
		set_meta("grab_report", true)
		print("CLIENT after being grabbed: unsold=", gs.unsold_photos.size(), " pos=", p.global_position.snapped(Vector3.ONE))
	if role == "host" and phase == 1 and t > 26.0:
		phase = 2
		m.call("_sleep")
	if role == "client" and phase == 3 and t > 36.0:
		phase = 4
		var cs = m.get("_cryptids")
		print("CLIENT after host slept: night=", gs.night, " puppets=", cs.size(), " remotes=", m.get("_net").remotes.keys())
	if role == "host" and phase == 2 and t > 36.0:
		phase = 3
		print("HOST after sleep: night=", gs.night, " ready=", m.get("_net")._ready_peers.keys(), " remotes=", m.get("_net").remotes.keys())
	if t > float(OS.get_environment("LIFE") if OS.get_environment("LIFE") != "" else "42"):
		quit()
	return false
