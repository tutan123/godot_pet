extends Node

## WebSocketClient.gd
## 处理与 JS 服务端的 WebSocket 通信，包含连接管理、心跳和消息路由。

signal message_received(type: String, data: Dictionary)
signal connected
signal disconnected

@export var websocket_url: String = "ws://localhost:8080"
@export var heartbeat_interval: float = 30.0

var socket := WebSocketPeer.new()
var last_heartbeat: float = 0.0
var _is_connected_to_server: bool = false # 重命名避免冲突

## 重连相关变量
var retry_intervals: Array = [1.0, 3.0, 5.0, 10.0, 30.0]
var retry_count: int = 0
var retry_timer: float = 0.0
var is_retrying: bool = false

func _ready() -> void:
	var config_manager = get_node_or_null("/root/Main/ConfigManager")
	if config_manager:
		websocket_url = config_manager.websocket_url
	connect_to_server()

func is_connected_to_server() -> bool:
	return _is_connected_to_server

func connect_to_server() -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		return
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.close()
		_is_connected_to_server = false
	
	print("Connecting to WebSocket server: ", websocket_url)
	var err = socket.connect_to_url(websocket_url)
	if err != OK:
		_start_retry_timer()
	else:
		set_process(true)

func _start_retry_timer() -> void:
	is_retrying = true
	var wait_time = retry_intervals[min(retry_count, retry_intervals.size() - 1)]
	print("Connection failed. Retrying in %.1f seconds..." % wait_time)
	retry_timer = wait_time
	retry_count += 1

func _process(delta: float) -> void:
	if is_retrying:
		retry_timer -= delta
		if retry_timer <= 0:
			is_retrying = false
			connect_to_server()
		return

	socket.poll()
	var state = socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not _is_connected_to_server:
			_is_connected_to_server = true
			retry_count = 0
			print("Connected to server!")
			connected.emit()
			_send_handshake()
		
		last_heartbeat += delta
		if last_heartbeat >= heartbeat_interval:
			send_message("heartbeat", {"timestamp": Time.get_unix_time_from_system()})
			last_heartbeat = 0.0
			
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			var message_str = packet.get_string_from_utf8()
			_handle_json_message(message_str)
			
	elif state == WebSocketPeer.STATE_CLOSED:
		if _is_connected_to_server or not is_retrying:
			_is_connected_to_server = false
			print("Disconnected from server.")
			disconnected.emit()
			_start_retry_timer()

func send_message(msg_type: String, data: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var message = {
		"type": msg_type,
		"timestamp": Time.get_unix_time_from_system(),
		"data": data
	}
	socket.send_text(JSON.stringify(message))

func _send_handshake() -> void:
	send_message("handshake", {
		"client_type": "godot_robot",
		"version": "1.0",
		"platform": OS.get_name()
	})

func _handle_json_message(json_str: String) -> void:
	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK: return
	var message = json.get_data()
	if typeof(message) != TYPE_DICTIONARY: return
	message_received.emit(message.get("type", ""), message.get("data", {}))
