extends Control

## settings_ui.gd
## 设置界面控制器

signal settings_saved()
signal settings_cancelled()

@onready var websocket_input: LineEdit = $Panel/VBoxContainer/ServerSettings/WebSocketInput
@onready var asr_input: LineEdit = $Panel/VBoxContainer/ASRSettings/ASRInput
@onready var save_button: Button = $Panel/VBoxContainer/Buttons/SaveButton
@onready var cancel_button: Button = $Panel/VBoxContainer/Buttons/CancelButton

var config_manager: Node

func _ready() -> void:
	config_manager = get_node("/root/Main/ConfigManager")
	if not config_manager:
		# 如果找不到ConfigManager，尝试从场景中获取
		config_manager = get_tree().get_first_node_in_group("config_manager")
	
	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	
	# 加载当前配置
	_load_current_config()

func _load_current_config() -> void:
	if config_manager:
		websocket_input.text = config_manager.websocket_url
		asr_input.text = config_manager.asr_websocket_url

func _on_save_pressed() -> void:
	if config_manager:
		config_manager.websocket_url = websocket_input.text.strip_edges()
		config_manager.asr_websocket_url = asr_input.text.strip_edges()
		config_manager.save_config()
		
		# 通知WebSocket客户端重新连接
		var ws_client = get_node("/root/Main/WebSocketClient")
		if ws_client:
			ws_client.websocket_url = config_manager.websocket_url
			ws_client.connect_to_server()
		
		# 通知ASR客户端更新URL
		var asr_client = get_node("/root/Main/ASRWebSocketClient")
		if asr_client:
			asr_client.asr_websocket_url = config_manager.asr_websocket_url
	
	settings_saved.emit()
	hide()

func _on_cancel_pressed() -> void:
	_load_current_config()  # 恢复原值
	settings_cancelled.emit()
	hide()

func _input(event: InputEvent) -> void:
	# 按ESC关闭设置窗口
	if visible and event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
