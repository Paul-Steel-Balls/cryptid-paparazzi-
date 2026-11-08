extends Node
## Autoload "Net": online co-op (up to 4 photographers). One PC hosts (it runs the cryptids,
## the night and the map); the others join it by IP address. Built on Godot's ENet peer.
##
## Who decides what:
##   host    - cryptid AI, spawns, bait/traps out in the world, the pot of gold, Santa,
##             when the night ends and which map you're on (only the host can sleep/drive).
##   each PC - its own player (movement is trusted), its own camera, photos, money and save.
## World traffic goes through the map's NetSync node (scripts/net_sync.gd).
##
## Quick start from the command line (handy for testing):
##   CryptidPaparazzi.exe -- --host            host on the default port
##   CryptidPaparazzi.exe -- --join=1.2.3.4    join that address
##   ... --name=Alex                            your name over your head

signal players_changed
signal joined_game          # we're connected to a host (client side)
signal connection_failed(reason: String)
signal left_game(reason: String)

const DEFAULT_PORT:= 24680
const MAX_PLAYERS:= 4

## peer id -> {"name": String, "color": Color}
var players: Dictionary = {}
var my_name:= "Photographer"
var last_error:= ""
var _peer: ENetMultiplayerPeer
var _colors:= [Color(0.95, 0.25, 0.2), Color(0.25, 0.55, 1.0), Color(0.3, 0.85, 0.35), Color(1.0, 0.75, 0.15)]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	var saved:= str(GameState.settings.get("player_name", ""))
	if saved != "":
		my_name = saved
	_parse_cmdline.call_deferred()
	GameState.skin_changed.connect(set_my_skin)


func _parse_cmdline() -> void:
	var host:= false
	var join:= ""
	for a in OS.get_cmdline_user_args():
		if a == "--host":
			host = true
		elif a.begins_with("--join="):
			join = a.substr(7)
		elif a.begins_with("--name="):
			my_name = a.substr(7)
	if host:
		host_game(DEFAULT_PORT)
	elif join != "":
		var parts:= join.split(":")
		join_game(parts[0], int(parts[1]) if parts.size() > 1 else DEFAULT_PORT)


# ------------------------------------------------------------------ status

func online() -> bool:
	return _peer != null and multiplayer.multiplayer_peer == _peer \
		and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return online() and multiplayer.is_server()


func is_client() -> bool:
	return online() and not multiplayer.is_server()


## True when this PC runs the world: single player, or hosting.
func has_authority() -> bool:
	return not online() or multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if online() else 1


func name_of(id: int) -> String:
	return str(players.get(id, {}).get("name", "Player %d" % id))


func color_of(id: int) -> Color:
	return players.get(id, {}).get("color", Color.WHITE)


func skin_of(id: int) -> String:
	return str(players.get(id, {}).get("skin", Skins.DEFAULT))


## You changed outfits: tell everyone (through the host).
func set_my_skin(id: String) -> void:
	if not online():
		return
	if is_host():
		if players.has(1):
			players[1]["skin"] = id
		_sync_players.rpc(players)
		players_changed.emit()
	else:
		_skin_update.rpc_id(1, id)


@rpc("any_peer", "reliable")
func _skin_update(id: String) -> void:
	if not multiplayer.is_server():
		return
	var who:= multiplayer.get_remote_sender_id()
	if players.has(who) and Skins.CATALOG.has(id):
		players[who]["skin"] = id
		_sync_players.rpc(players)
		players_changed.emit()


## Addresses other people on your network can use to reach this PC.
func local_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


# ------------------------------------------------------------------ host / join / leave

func host_game(port: int = DEFAULT_PORT) -> bool:
	leave("")
	_peer = ENetMultiplayerPeer.new()
	var err:= _peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		last_error = "Couldn't host on port %d (is it already in use?)" % port
		_peer = null
		connection_failed.emit(last_error)
		return false
	multiplayer.multiplayer_peer = _peer
	players = {1: {"name": my_name, "color": _colors[0], "skin": GameState.skin}}
	players_changed.emit()
	print("NET hosting on port ", port)
	return true


func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	leave("")
	_peer = ENetMultiplayerPeer.new()
	var err:= _peer.create_client(address.strip_edges(), port)
	if err != OK:
		last_error = "Couldn't reach %s:%d" % [address, port]
		_peer = null
		connection_failed.emit(last_error)
		return false
	multiplayer.multiplayer_peer = _peer
	print("NET joining ", address, ":", port)
	return true


func connecting() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING


func leave(reason: String = "You left the game.") -> void:
	var was:= _peer != null
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	if was:
		players_changed.emit()
		if reason != "":
			left_game.emit(reason)


func set_my_name(n: String) -> void:
	n = n.strip_edges().left(16)
	if n == "":
		return
	my_name = n
	GameState.settings["player_name"] = n
	GameState.save_settings()


# ------------------------------------------------------------------ callbacks

func _on_peer_connected(id: int) -> void:
	print("NET peer connected ", id)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		players.erase(id)
		_sync_players.rpc(players)
		players_changed.emit()


func _on_connected() -> void:
	print("NET connected as ", multiplayer.get_unique_id())
	_register.rpc_id(1, my_name, GameState.skin)


func _on_failed() -> void:
	last_error = "Couldn't connect. Check the address, that the host is running, and their port forwarding / firewall."
	leave("")
	connection_failed.emit(last_error)


func _on_server_gone() -> void:
	leave("The host closed the game.")


## A new arrival tells the host its name; the host hands out colours and tells everyone.
@rpc("any_peer", "reliable")
func _register(pname: String, skin: String = "default") -> void:
	if not multiplayer.is_server():
		return
	var id:= multiplayer.get_remote_sender_id()
	if players.size() >= MAX_PLAYERS:
		_peer.disconnect_peer(id)
		return
	var used: Array = []
	for k in players:
		used.append(players[k]["color"])
	var col: Color = _colors[players.size() % _colors.size()]
	for c in _colors:
		if c not in used:
			col = c
			break
	players[id] = {"name": pname.strip_edges().left(16) if pname.strip_edges() != "" else "Player %d" % id, "color": col,
		"skin": skin if Skins.CATALOG.has(skin) else Skins.DEFAULT}
	_sync_players.rpc(players)
	players_changed.emit()
	# Bring them to the host's map and night.
	_welcome.rpc_id(id, GameState.current_map, GameState.night)


@rpc("authority", "reliable")
func _sync_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()


## Client: the host is on this map, this night. Load it (the map's NetSync takes over from there).
@rpc("authority", "reliable")
func _welcome(map_id: String, night: int) -> void:
	GameState.current_map = map_id
	GameState.night = night
	GameState.arrival = "join"
	joined_game.emit()
	get_tree().paused = false
	get_tree().reload_current_scene.call_deferred()
