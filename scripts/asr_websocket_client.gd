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
	
	# 【核心修复】扩容缓冲区，防止 Error 6 (ERR_OUT_OF_MEMORY)
	# 48kHz PCM 数据很大，默认 64KB 缓冲区不够用
	socket.inbound_buffer_size = 1024 * 1024 * 4 # 4MB
	socket.outbound_buffer_size = 1024 * 1024 * 4 # 4MB
	
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
	if not is_connected:
		# 只有在完全没有网络连接时才跳过
		return
	
	# 发送音频数据（后端会自动识别或创建会话）
	socket.send(audio_data)

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
		# 服务端可能在顶层有text，也可能在data里有text
		var text = message.get("text", "")
		var data = message.get("data", {})
		if text == "" and data:
			text = data.get("text", "")
		# is_final可能在顶层，也可能在data里（但ASRResult模型里没有，所以通常为false）
		var is_final = message.get("is_final", false)
		if not is_final and data:
			is_final = data.get("is_final", false)
		print("[ASR] Result received - text: ", text, ", is_final: ", is_final)
		if text != "":
			recognition_result.emit(text, is_final)
			
	elif status == "ended":
		var final_result = message.get("final_result", {})
		print("[ASR] Session ended, final_result: ", final_result)
		if final_result:
			var text = final_result.get("text", "")
			print("[ASR] Final result text: ", text)
			if text != "":
				recognition_result.emit(text, true)
		else:
			# 如果没有final_result，尝试从data里获取
			var data = message.get("data", {})
			if data:
				var text = data.get("text", "")
				if text != "":
					print("[ASR] Using data.text as final result: ", text)
					recognition_result.emit(text, true)
		session_id = ""
		session_ended.emit()
		
	elif status == "error":
		var error_msg = message.get("message", "未知错误")
		error_occurred.emit(error_msg)
		print("ASR error: ", error_msg)
