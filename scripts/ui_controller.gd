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
	if ws_client:
		ws_client.message_received.connect(_on_ws_message)
		ws_client.connected.connect(func(): _log("Connected to server."))
		ws_client.disconnected.connect(func(): _log("Disconnected from server."))

func _on_send_pressed() -> void:
	_send_input()

func _on_text_submitted(_text: String) -> void:
	_send_input()

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
		if content != "":
			_log("[color=green]Pet: [/color]" + content)
	elif type == "status_update":
		# 可以更新 UI 上的状态条，这里先忽略
		pass

func _log(msg: String) -> void:
	chat_log.append_text(msg + "\n")
