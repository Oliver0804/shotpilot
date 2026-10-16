@tool
extends RefCounted
## WebSocket 伺服器 + UDP 廣播信標（讓手機 App 自動找到這台電腦）。
## 需由擁有者每幀呼叫 poll()。

signal message(peer_id: int, data: Dictionary)
signal clients_changed(count: int)

const BEACON_PORT := 47011
const BEACON_INTERVAL := 1.0
const BUFFER_SIZE := 4 * 1024 * 1024 # 影像幀可能超過預設 64KB
const CONGESTION_BYTES := 512 * 1024

var port := 8765
var client_count := 0

var _tcp := TCPServer.new()
var _udp := PacketPeerUDP.new()
var _peers := {} # id -> WebSocketPeer
var _next_id := 1
var _beacon_t := 0.0


func start(p_port: int) -> Error:
	stop()
	port = p_port
	var err := _tcp.listen(port)
	if err != OK:
		return err
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", BEACON_PORT)
	_beacon_t = BEACON_INTERVAL
	return OK


func stop() -> void:
	for ws: WebSocketPeer in _peers.values():
		ws.close()
	_peers.clear()
	_tcp.stop()
	_udp.close()
	_set_count(0)


func is_running() -> bool:
	return _tcp.is_listening()


func poll(delta: float) -> void:
	if not _tcp.is_listening():
		return

	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.outbound_buffer_size = BUFFER_SIZE
		ws.inbound_buffer_size = BUFFER_SIZE
		if ws.accept_stream(_tcp.take_connection()) == OK:
			_peers[_next_id] = ws
			_next_id += 1

	var open := 0
	for id: int in _peers.keys():
		var ws: WebSocketPeer = _peers[id]
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				open += 1
				while ws.get_available_packet_count() > 0:
					var data = JSON.parse_string(ws.get_packet().get_string_from_utf8())
					if data is Dictionary:
						message.emit(id, data)
			WebSocketPeer.STATE_CLOSED:
				_peers.erase(id)
	_set_count(open)

	_beacon_t += delta
	if _beacon_t >= BEACON_INTERVAL:
		_beacon_t = 0.0
		var beacon := {"phonecam": 1, "port": port, "name": OS.get_environment("USER")}
		_udp.put_packet(JSON.stringify(beacon).to_utf8_buffer())


func broadcast(data: Dictionary) -> void:
	var text := JSON.stringify(data)
	for ws: WebSocketPeer in _peers.values():
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(text)


func broadcast_binary(bytes: PackedByteArray) -> void:
	for ws: WebSocketPeer in _peers.values():
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)


func is_congested() -> bool:
	for ws: WebSocketPeer in _peers.values():
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN \
				and ws.get_current_outbound_buffered_amount() > CONGESTION_BYTES:
			return true
	return false


static func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	return out


func _set_count(n: int) -> void:
	if n != client_count:
		client_count = n
		clients_changed.emit(n)
