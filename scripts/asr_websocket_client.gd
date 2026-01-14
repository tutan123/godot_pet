extends Node

## ASRWebSocketClient.gd
## ASR服务的WebSocket客户端，处理流式语音识别

signal recognition_result(text: String, is_final: bool)
signal session_started(session_id: String)
signal session_ended()
signal error_occurred(message: String)

@export var asr_websocket_url: String = "ws://localhost:8000/api/v1/realtime"

var socket := WebSocketPeer.new()
var is_connected: bool = false
var session_id: String = ""
var is_recording: bool = false

func _ready() -> void:
	# 从ConfigManager加载配置
	var config_manager = get_node("/root/Main/ConfigManager")
	if config_manager:
		asr_websocket_url = config_manager.asr_websocket_url

func connect_to_server() -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN or socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		socket.close()
		is_connected = false
	
	print("Connecting to ASR WebSocket server: ", asr_websocket_url)
	var err = socket.connect_to_url(asr_websocket_url)
	if err != OK:
		print("Unable to connect to ASR server, error code: ", err)
		error_occurred.emit("连接ASR服务失败: " + str(err))
		set_process(false)
	else:
		set_process(true)

func _process(delta: float) -> void:
	socket.poll()
	
	var state = socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			is_connected = true
			print("Connected to ASR server!")
		
		# 读取待处理消息
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			var message_str = packet.get_string_from_utf8()
			_handle_message(message_str)
			
	elif state == WebSocketPeer.STATE_CLOSING:
		pass
	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected:
			is_connected = false
			print("Disconnected from ASR server.")
			session_id = ""

func start_session() -> void:
	if not is_connected:
		connect_to_server()
		# 等待连接建立
		await get_tree().create_timer(0.5).timeout
		if not is_connected:
			error_occurred.emit("无法连接到ASR服务")
			return
	
	if session_id != "":
		# 已有会话，先结束
		end_session()
		await get_tree().create_timer(0.2).timeout
	
	var message = {
		"type": "start",
		"config": {
			"sample_rate": 48000, # 匹配 Godot 的录音采样率
			"language": "zh",
			"use_itn": true,
			"vad_enabled": true,
			"emotion_detection": false,
			"event_detection": false,
			"chunk_size": 600,
			"merge_vad": true,
			"merge_length_s": 15
		}
	}
	
	_send_json(message)

func send_audio(audio_data: PackedByteArray) -> void:
	if not is_connected or session_id == "":
		return
	
	# 【优化】使用二进制发送，不再使用 Base64 包装 JSON，速度提升一倍以上
	socket.send_binary(audio_data)

func end_session() -> void:
	if session_id == "":
		return
	
	var message = {
		"type": "end"
	}
	
	_send_json(message)
	session_id = ""

func _send_json(data: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("Cannot send message, ASR socket not open.")
		return
	
	var json_str = JSON.stringify(data)
	socket.send_text(json_str)

func _handle_message(json_str: String) -> void:
	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK:
		print("ASR JSON Parse Error: ", json.get_error_message(), " in ", json_str)
		return
	
	var message = json.get_data()
	if typeof(message) != TYPE_DICTIONARY:
		print("Invalid ASR message format: expected Dictionary.")
		return
	
	var status = message.get("status", "")
	
	if status == "started":
		session_id = message.get("session_id", "")
		session_started.emit(session_id)
		print("ASR session started: ", session_id)
		
	elif status == "result":
		var data = message.get("data", {})
		var text = data.get("text", "")
		var is_final = data.get("is_final", false)
		if text != "":
			recognition_result.emit(text, is_final)
			
	elif status == "ended":
		var final_result = message.get("final_result", {})
		if final_result:
			var text = final_result.get("text", "")
			if text != "":
				recognition_result.emit(text, true)
		session_id = ""
		session_ended.emit()
		
	elif status == "error":
		var error_msg = message.get("message", "未知错误")
		error_occurred.emit(error_msg)
		print("ASR error: ", error_msg)
