extends Control

## UIController.gd
## 处理用户输入界面，将文本指令发送给 WebSocketClient。

@onready var input_edit: LineEdit = $Panel/HBoxContainer/LineEdit
@onready var send_button: Button = $Panel/HBoxContainer/Button
@onready var reconnect_button: Button = $Panel/HBoxContainer/ReconnectButton
@onready var voice_button: Button = $Panel/HBoxContainer/VoiceButton
@onready var settings_button: Button = $Panel/HBoxContainer/SettingsButton
@onready var welcome_button: Button = $WelcomeButton
@onready var chat_log: RichTextLabel = $Panel/VBoxContainer/RichTextLabel
@onready var settings_panel: Control = $Settings
@onready var ws_client = get_node("/root/Main/WebSocketClient")
@onready var asr_client = get_node("/root/Main/ASRWebSocketClient")
@onready var audio_recorder = get_node("/root/Main/AudioRecorder")

var is_voice_recording: bool = false
var recording_timer: Timer

func _ready() -> void:
	send_button.pressed.connect(_on_send_pressed)
	if reconnect_button:
		reconnect_button.pressed.connect(_on_reconnect_pressed)
	if voice_button:
		voice_button.button_down.connect(_on_voice_button_down)
		voice_button.button_up.connect(_on_voice_button_up)
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if welcome_button:
		welcome_button.pressed.connect(_on_welcome_pressed)
	input_edit.text_submitted.connect(_on_text_submitted)
	# 当输入框失去焦点时，释放键盘输入，允许WASD移动
	input_edit.focus_exited.connect(_on_input_focus_exited)
	if ws_client:
		ws_client.message_received.connect(_on_ws_message)
		ws_client.connected.connect(_on_ws_connected)
		ws_client.disconnected.connect(_on_ws_disconnected)
		_update_reconnect_button_state()
	
	# 连接ASR客户端信号
	if asr_client:
		asr_client.recognition_result.connect(_on_asr_result)
		asr_client.error_occurred.connect(_on_asr_error)
	
	# 创建录音定时器
	recording_timer = Timer.new()
	recording_timer.wait_time = 0.1  # 每100ms发送一次音频
	recording_timer.timeout.connect(_on_recording_timer_timeout)
	add_child(recording_timer)

func _process(_delta: float) -> void:
	# 定期更新重连按钮状态（防止信号丢失）
	if reconnect_button and ws_client:
		var should_be_disabled = ws_client.is_connected_to_server()
		if reconnect_button.disabled != should_be_disabled:
			_update_reconnect_button_state()

func _input(event: InputEvent) -> void:
	# 关键修复：点击聊天面板 ($Panel) 以外的任何区域，都立即释放焦点
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos = get_viewport().get_mouse_position()
		var panel: Panel = $Panel
		if panel and not panel.get_global_rect().has_point(mouse_pos):
			input_edit.release_focus()

func _on_send_pressed() -> void:
	_send_input()

func _on_text_submitted(_text: String) -> void:
	_send_input()
	# 发送后自动释放焦点，让WASD可以控制角色移动
	input_edit.release_focus()

func _on_input_focus_exited() -> void:
	# 输入框失去焦点时，确保键盘输入可以用于角色移动
	# Godot 会自动处理焦点释放后的输入路由
	pass

func _send_input() -> void:
	var text = input_edit.text.strip_edges()
	if text == "":
		return
		
	if ws_client and ws_client.is_connected_to_server():
		ws_client.send_message("user_input", {"text": text})
		_log("[color=blue]You: [/color]" + text)
		input_edit.clear()
	else:
		_log("[color=red]System: Not connected to server.[/color]")

func _on_ws_message(type: String, data: Dictionary) -> void:
	if type == "chat":
		var content = data.get("content", "")
		var role = data.get("role", "model")
		var is_tool_call = data.get("isToolCall", false)
		
		if content != "":
			if role == "system":
				_log("[color=gray]<i>" + content + "</i>[/color]")
			elif is_tool_call:
				_log("[color=yellow][Action] " + content + "[/color]")
			else:
				_log("[color=green]Pet: [/color]" + content)
	elif type == "status_update":
		# 可以更新 UI 上的状态条，这里先忽略
		pass

func _on_reconnect_pressed() -> void:
	if ws_client:
		_log("[color=yellow]System: Attempting to reconnect...[/color]")
		ws_client.connect_to_server()

func _on_ws_connected() -> void:
	_log("[color=green]System: Connected to server.[/color]")
	_update_reconnect_button_state()

func _on_ws_disconnected() -> void:
	_log("[color=red]System: Disconnected from server.[/color]")
	_update_reconnect_button_state()

func _update_reconnect_button_state() -> void:
	if reconnect_button and ws_client:
		reconnect_button.disabled = ws_client.is_connected_to_server()
		if ws_client.is_connected_to_server():
			reconnect_button.text = "Connected"
		else:
			reconnect_button.text = "Reconnect"

func _log(msg: String) -> void:
	chat_log.append_text(msg + "\n")

func _on_settings_pressed() -> void:
	if settings_panel:
		settings_panel.visible = true
		settings_panel.set_process_mode(Node.PROCESS_MODE_ALWAYS)

func _on_voice_button_down() -> void:
	if not asr_client or not audio_recorder:
		_log("[color=red]System: ASR服务未初始化[/color]")
		return
	
	if not asr_client.is_connected:
		_log("[color=yellow]System: 正在连接ASR服务...[/color]")
		asr_client.connect_to_server()
		await get_tree().create_timer(0.5).timeout
	
	if not asr_client.is_connected:
		_log("[color=red]System: 无法连接到ASR服务[/color]")
		return
	
	# 开始录音
	is_voice_recording = true
	audio_recorder.start_recording()
	asr_client.start_session()
	recording_timer.start()
	
	voice_button.modulate = Color(1, 0.5, 0.5)  # 变红表示正在录音
	_log("[color=cyan]System: 开始语音输入...[/color]")

func _on_voice_button_up() -> void:
	if not is_voice_recording:
		return
	
	print("[UI] Voice button up - stopping recording...")
	is_voice_recording = false
	recording_timer.stop()
	
	# 【核心优化】停止定时器后，直接发送最后一整块完整的、高质量的音频数据
	# 不再依赖之前的零碎块，由这一块决定最终识别结果
	var audio_data = await audio_recorder.stop_recording()
	print("[UI] Final recording data size: ", audio_data.size())
	
	if audio_data.size() > 0:
		asr_client.send_audio(audio_data)
		print("[UI] Sent final audio chunk, waiting for recognition...")
	
	# 增加等待时间，确保最后一整块音频的识别结果能够返回
	# 服务端的end_session会等待0.3秒，所以这里等待0.5秒应该足够
	await get_tree().create_timer(0.5).timeout
	print("[UI] Ending ASR session...")
	asr_client.end_session()
	voice_button.modulate = Color(1, 1, 1)

func _on_recording_timer_timeout() -> void:
	# 【优化】临时禁用定时器发送碎片数据，改为松开按钮时发送全量
	# 碎片化发送会导致 SenseVoice 多次重复识别相同内容
	return

func _on_asr_result(text: String, is_final: bool) -> void:
	print("[UI] ASR result received - text: '", text, "', is_final: ", is_final, ", is_voice_recording: ", is_voice_recording)
	if text != "":
		if is_final:
			# 最终结果，填入输入框并自动发送
			input_edit.text = text
			_log("[color=cyan]System: 识别结果: " + text + "[/color]")
			print("[UI] Auto-sending final result: ", text)
			# 自动发送识别结果
			_send_input()
		else:
			# 中间结果，可以显示在输入框或日志中
			# 这里选择显示在输入框，用户可以编辑
			if not is_voice_recording:
				input_edit.text = text

func _on_asr_error(message: String) -> void:
	_log("[color=red]System: ASR错误: " + message + "[/color]")

func _on_welcome_pressed() -> void:
	# 触发迎宾场景
	if ws_client and ws_client.is_connected_to_server():
		ws_client.send_message("scene_trigger", {"scene": "welcome"})
		_log("[color=yellow]System: 触发迎宾场景[/color]")
	else:
		_log("[color=red]System: 未连接到服务器，无法触发场景[/color]")
