class_name MobileUIController
extends Node3D

# 核心属性
@export var websocket_url: String = "ws://localhost:8080"
@export var ui_scale: Vector3 = Vector3(0.1, 0.1, 0.1)
@export var interaction_distance: float = 5.0
@export var auto_reconnect: bool = true
@export var reconnect_interval: float = 3.0

# 子系统引用
var websocket_client: WebSocketClient
var ui_renderer: Node
var interaction_handler: Node
var state_sync: Node

# UI面板集合
var ui_panels: Dictionary = {}
var panel_configs: Dictionary = {}

# 连接状态
var is_connected: bool = false
var reconnect_timer: Timer

# 信号
signal mobile_connected(device_info: Dictionary)
signal mobile_disconnected()
signal ui_panel_created(panel_id: String, panel: Node3D)
signal ui_panel_updated(panel_id: String, updates: Dictionary)
signal interaction_received(panel_id: String, event_type: String, event_data: Dictionary)

func _ready():
	_initialize_subsystems()
	_connect_signals()
	_setup_reconnect_timer()

func _initialize_subsystems():
	# 初始化WebSocket客户端
	websocket_client = WebSocketClient.new()
	add_child(websocket_client)

	# 初始化3D UI渲染器
	ui_renderer = load("res://scripts/mobile_ui/ui_renderer_3d.gd").new()
	add_child(ui_renderer)

	# 初始化交互处理器
	interaction_handler = load("res://scripts/mobile_ui/interaction_handler.gd").new()
	add_child(interaction_handler)

	# 初始化状态同步器
	state_sync = load("res://scripts/mobile_ui/state_synchronizer.gd").new()
	add_child(state_sync)

func _connect_signals():
	# WebSocket信号连接
	websocket_client.connected.connect(_on_websocket_connected)
	websocket_client.disconnected.connect(_on_websocket_disconnected)
	websocket_client.message_received.connect(_on_websocket_message)

	# UI渲染器信号连接
	ui_renderer.panel_created.connect(_on_panel_created)
	ui_renderer.panel_updated.connect(_on_panel_updated)

	# 连接到全局 WebSocket 客户端
	var ws_client = get_node_or_null("/root/Main/WebSocketClient")
	if ws_client:
		if not ws_client.message_received.is_connected(_on_websocket_message):
			ws_client.message_received.connect(_on_websocket_message)
			print("[MobileUI] Successfully connected to WebSocketClient signal")
		else:
			print("[MobileUI] WebSocketClient signal already connected")
	else:
		print("[MobileUI] Warning: WebSocketClient not found at /root/Main/WebSocketClient")

	# 交互处理器信号连接
	interaction_handler.interaction_detected.connect(_on_interaction_detected)

func _on_websocket_message(type: String, data: Dictionary):
	# 统一路由 UI 相关消息
	print("[MobileUI] Received message type: ", type)
	match type:
		"connected":
			_handle_mobile_connected(data)
		"ui_sync":
			_handle_ui_sync(data)
		"create_panel":
			_handle_create_panel(data)
		"update_panel":
			_handle_update_panel(data)
		"remove_panel":
			_handle_remove_panel(data)
		"gesture":
			_handle_gesture(data)
		"sensor_data":
			_handle_sensor_data(data)
		_:
			# 忽略非 UI 消息
			print("[MobileUI] Ignoring non-UI message type: ", type)
			pass

func _setup_reconnect_timer():
	reconnect_timer = Timer.new()
	reconnect_timer.wait_time = reconnect_interval
	reconnect_timer.one_shot = true
	reconnect_timer.timeout.connect(_try_reconnect)
	add_child(reconnect_timer)

# 连接到手机设备
func connect_to_mobile(url: String = ""):
	if url != "":
		websocket_url = url

	if websocket_client:
		websocket_client.connect_to_url(websocket_url)

# 断开连接
func disconnect_mobile():
	if websocket_client:
		websocket_client.disconnect_from_host()
	is_connected = false

# 创建手机UI面板
func create_mobile_ui_panel(panel_id: String, config: Dictionary):
	if ui_renderer:
		var panel = ui_renderer.create_panel(panel_id, config)
		ui_panels[panel_id] = panel
		panel_configs[panel_id] = config
		return panel
	return null

# 更新UI面板
func update_mobile_ui_panel(panel_id: String, updates: Dictionary):
	if ui_panels.has(panel_id) and ui_renderer:
		ui_renderer.update_panel(panel_id, updates)

# 删除UI面板
func remove_mobile_ui_panel(panel_id: String):
	if ui_panels.has(panel_id):
		if ui_renderer:
			ui_renderer.remove_panel(panel_id)
		ui_panels.erase(panel_id)
		panel_configs.erase(panel_id)

# 发送交互事件到手机
func send_interaction_to_mobile(panel_id: String, event_type: String, event_data: Dictionary):
	if websocket_client and is_connected:
		var message = {
			"type": "interaction",
			"panel_id": panel_id,
			"event_type": event_type,
			"event_data": event_data,
			"timestamp": Time.get_unix_time_from_system()
		}
		websocket_client.send_json(message)

# 缩放UI面板
func scale_ui_panel(panel_id: String, scale_factor: float):
	if ui_panels.has(panel_id):
		var panel = ui_panels[panel_id]
		panel.scale *= scale_factor

		# 通知手机端
		send_interaction_to_mobile(panel_id, "scale_changed", {
			"scale": panel.scale,
			"scale_factor": scale_factor
		})

# 旋转UI面板
func rotate_ui_panel(panel_id: String, rotation: Vector3):
	if ui_panels.has(panel_id):
		var panel = ui_panels[panel_id]
		panel.rotation = rotation

		# 通知手机端
		send_interaction_to_mobile(panel_id, "rotation_changed", {
			"rotation": rotation
		})

# 平移UI面板
func move_ui_panel(panel_id: String, new_position: Vector3):
	if ui_panels.has(panel_id):
		var panel = ui_panels[panel_id]
		panel.position = new_position

		# 通知手机端
		send_interaction_to_mobile(panel_id, "position_changed", {
			"position": new_position
		})

# 获取面板信息
func get_panel_info(panel_id: String) -> Dictionary:
	if ui_panels.has(panel_id):
		var panel = ui_panels[panel_id]
		return {
			"position": panel.position,
			"rotation": panel.rotation,
			"scale": panel.scale,
			"visible": panel.visible,
			"config": panel_configs.get(panel_id, {})
		}
	return {}

# 获取所有面板信息
func get_all_panels_info() -> Dictionary:
	var info = {}
	for panel_id in ui_panels.keys():
		info[panel_id] = get_panel_info(panel_id)
	return info

# WebSocket事件处理
func _on_websocket_connected():
	is_connected = true
	print("Connected to mobile device at: ", websocket_url)

	# 发送连接信息
	var connect_message = {
		"type": "connect",
		"client_type": "godot_3d_ui",
		"capabilities": {
			"ui_rendering": true,
			"interaction": true,
			"gesture_support": true,
			"multi_touch": true
		},
		"supported_panel_types": ["form", "button", "text", "list", "custom"]
	}
	websocket_client.send_json(connect_message)

func _on_websocket_disconnected():
	is_connected = false
	print("Disconnected from mobile device")

	mobile_disconnected.emit()

	if auto_reconnect:
		reconnect_timer.start()


func _handle_mobile_connected(message: Dictionary):
	var device_info = message.get("device_info", {})
	print("Mobile device connected: ", device_info)
	mobile_connected.emit(device_info)

func _handle_create_panel(message: Dictionary):
	var panel_id = message.get("panel_id", "")
	var config = message.get("config", {})

	if panel_id != "":
		create_mobile_ui_panel(panel_id, config)

func _handle_update_panel(message: Dictionary):
	var panel_id = message.get("panel_id", "")
	var updates = message.get("updates", {})

	if panel_id != "":
		update_mobile_ui_panel(panel_id, updates)

func _handle_remove_panel(message: Dictionary):
	var panel_id = message.get("panel_id", "")

	if panel_id != "":
		remove_mobile_ui_panel(panel_id)

func _handle_ui_sync(message: Dictionary):
	print("[MobileUI] UI Sync: Received ui_sync message")
	print("[MobileUI] UI Sync: Raw message: ", message)

	var data = message.get("data", message) # 兼容不同层级
	print("[MobileUI] UI Sync: Extracted data: ", data)

	var panel_id = data.get("panel_id", "mobile_ui_projected")
	var config = data.get("config", {})
	print("[MobileUI] UI Sync: Panel ID: ", panel_id)
	print("[MobileUI] UI Sync: Config: ", config)

	if not ui_panels.has(panel_id):
		print("[MobileUI] UI Sync: Panel ", panel_id, " does not exist, creating new panel")
		# 如果面板不存在，在角色面前创建一个默认位置的面板
		if config.is_empty():
			print("[MobileUI] UI Sync: Config is empty, skipping panel creation")
			return

		# 获取角色当前位置的前方
		var parent_node = get_parent()
		var spawn_pos = Vector3(0, 1.5, -2) # 默认相对位置

		if parent_node is Node3D:
			spawn_pos = parent_node.global_position + parent_node.global_transform.basis.z * -2.0 + Vector3(0, 1.5, 0)
			print("[MobileUI] UI Sync: Calculated spawn position: ", spawn_pos)

		config["position"] = spawn_pos
		print("[MobileUI] UI Sync: Creating mobile UI panel with config: ", config)
		create_mobile_ui_panel(panel_id, config)
		print("[MobileUI] UI Sync: Panel creation completed")
	else:
		print("[MobileUI] UI Sync: Panel ", panel_id, " already exists, updating content")
		# 如果面板已存在，更新其内容
		var updates = {
			"content": config.get("content", {})
		}
		print("[MobileUI] UI Sync: Updating panel with: ", updates)
		update_mobile_ui_panel(panel_id, updates)
		print("[MobileUI] UI Sync: Panel update completed")

func _handle_gesture(message: Dictionary):
	var gesture_type = message.get("gesture_type", "")
	var gesture_data = message.get("gesture_data", {})

	# 将手势转发给交互处理器
	if interaction_handler:
		interaction_handler.process_gesture(gesture_type, gesture_data)

func _handle_sensor_data(message: Dictionary):
	var sensor_data = message.get("sensor_data", {})

	# 处理传感器数据（可用于UI自适应）
	_adapt_ui_to_sensor_data(sensor_data)

# UI自适应处理
func _adapt_ui_to_sensor_data(sensor_data: Dictionary):
	# 根据设备方向调整UI
	if sensor_data.has("orientation"):
		var orientation = sensor_data.orientation
		_adjust_ui_for_orientation(orientation)

	# 根据距离调整UI大小
	if sensor_data.has("distance"):
		var distance = sensor_data.distance
		_adjust_ui_for_distance(distance)

func _adjust_ui_for_orientation(orientation: Vector3):
	# 根据设备方向调整UI朝向
	for panel_id in ui_panels.keys():
		var panel = ui_panels[panel_id]
		# 简单的朝向调整逻辑
		var target_rotation = orientation
		panel.rotation = panel.rotation.lerp(target_rotation, 0.1)

func _adjust_ui_for_distance(distance: float):
	# 根据距离调整UI大小
	var scale_factor = clamp(1.0 / distance, 0.05, 0.5)

	for panel_id in ui_panels.keys():
		var panel = ui_panels[panel_id]
		var target_scale = Vector3(scale_factor, scale_factor, scale_factor)
		panel.scale = panel.scale.lerp(target_scale, 0.1)

# 面板事件处理
func _on_panel_created(panel_id: String, panel: Node3D):
	ui_panel_created.emit(panel_id, panel)

func _on_panel_updated(panel_id: String, updates: Dictionary):
	ui_panel_updated.emit(panel_id, updates)

func _on_interaction_detected(panel_id: String, event_type: String, event_data: Dictionary):
	# 发送交互事件到手机
	send_interaction_to_mobile(panel_id, event_type, event_data)

	# 触发本地信号
	interaction_received.emit(panel_id, event_type, event_data)

# 重连处理
func _try_reconnect():
	if not is_connected and auto_reconnect:
		print("Attempting to reconnect to mobile device...")
		connect_to_mobile()

# 手动触发UI同步测试（用于调试）
func test_ui_sync() -> void:
	print("[MobileUI] Testing UI sync manually...")
	var test_ui_data = {
		"panel_id": "test_mobile_panel",
		"config": {
			"type": "form",
			"size": Vector2(400, 300),
			"content": {
				"title": "测试移动UI面板",
				"fields": [
					{"label": "测试字段", "input_type": "text", "value": "测试值"}
				],
				"buttons": [
					{"text": "测试按钮", "action": "test"}
				]
			}
		}
	}
	_handle_ui_sync(test_ui_data)

# 清理资源
func _exit_tree():
	disconnect_mobile()
	if reconnect_timer:
		reconnect_timer.stop()
