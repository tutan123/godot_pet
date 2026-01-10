extends Control

## UIController.gd
## 处理用户输入界面，将文本指令发送给 WebSocketClient。

@onready var input_edit: LineEdit = $Panel/HBoxContainer/LineEdit
@onready var send_button: Button = $Panel/HBoxContainer/Button
@onready var chat_log: RichTextLabel = $Panel/VBoxContainer/RichTextLabel
@onready var ws_client = get_node("/root/Main/WebSocketClient")

func _ready() -> void:
	send_button.pressed.connect(_on_send_pressed)
	input_edit.text_submitted.connect(_on_text_submitted)
	# 当输入框失去焦点时，释放键盘输入，允许WASD移动
	input_edit.focus_exited.connect(_on_input_focus_exited)
	if ws_client:
		ws_client.message_received.connect(_on_ws_message)
		ws_client.connected.connect(func(): _log("Connected to server."))
		ws_client.disconnected.connect(func(): _log("Disconnected from server."))

func _input(event: InputEvent) -> void:
	# 修复：点击 UI 以外的区域时，释放输入框焦点
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos = get_viewport().get_mouse_position()
		if not get_rect().has_point(mouse_pos):
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
		
	if ws_client and ws_client.is_connected:
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

func _log(msg: String) -> void:
	chat_log.append_text(msg + "\n")
