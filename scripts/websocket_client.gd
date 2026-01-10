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
var is_connected: bool = false

func _ready() -> void:
	connect_to_server()

func connect_to_server() -> void:
	# 如果已有连接，先关闭
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN or socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		socket.close()
		is_connected = false
	
	print("Connecting to WebSocket server: ", websocket_url)
	var err = socket.connect_to_url(websocket_url)
	if err != OK:
		print("Unable to connect to server, error code: ", err)
		set_process(false)
	else:
		set_process(true)

func _process(delta: float) -> void:
	socket.poll()
	
	var state = socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			is_connected = true
			print("Connected to server!")
			connected.emit()
			_send_handshake()
		
		# 处理心跳
		last_heartbeat += delta
		if last_heartbeat >= heartbeat_interval:
			send_message("heartbeat", {"timestamp": Time.get_unix_time_from_system()})
			last_heartbeat = 0.0
			
		# 读取待处理消息
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			var message_str = packet.get_string_from_utf8()
			_handle_json_message(message_str)
			
	elif state == WebSocketPeer.STATE_CLOSING:
		pass
	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected:
			is_connected = false
			print("Disconnected from server.")
			disconnected.emit()

func send_message(type: String, data: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("Cannot send message, socket not open.")
		return
		
	var message = {
		"type": type,
		"timestamp": Time.get_unix_time_from_system(),
		"data": data
	}
	
	var json_str = JSON.stringify(message)
	socket.send_text(json_str)

func _send_handshake() -> void:
	send_message("handshake", {
		"client_type": "godot_robot",
		"version": "1.0",
		"platform": OS.get_name()
	})

func _handle_json_message(json_str: String) -> void:
	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK:
		print("JSON Parse Error: ", json.get_error_message(), " in ", json_str)
		return
		
	var message = json.get_data()
	if typeof(message) != TYPE_DICTIONARY:
		print("Invalid message format: expected Dictionary.")
		return
		
	var type = message.get("type", "unknown")
	var data = message.get("data", {})
	
	# print("Received message: ", type, data)
	message_received.emit(type, data)
