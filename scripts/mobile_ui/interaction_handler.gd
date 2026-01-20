class_name InteractionHandler
extends Node

# 交互配置
@export var ray_length: float = 1000.0
@export var interaction_layer: int = 1
@export var multi_touch_enabled: bool = true
@export var gesture_recognition_enabled: bool = true

# 相机引用
var camera: Camera3D
var mobile_ui_controller: Node

# 交互状态
var current_panel_id: String = ""
var is_dragging: bool = false
var drag_start_position: Vector3
var last_interaction_time: float = 0.0

# 多指跟踪
var touch_points: Dictionary = {}
var gesture_recognizer: Node

# 信号
signal interaction_detected(panel_id: String, event_type: String, event_data: Dictionary)
signal gesture_detected(gesture_type: String, gesture_data: Dictionary)
signal drag_started(panel_id: String, start_position: Vector3)
signal drag_ended(panel_id: String, end_position: Vector3)

func _ready():
	_find_camera()
	_initialize_gesture_recognizer()

func _find_camera():
	# 查找场景中的相机
	camera = get_viewport().get_camera_3d()
	if not camera:
		# 尝试查找标记为MainCamera的节点
		camera = get_tree().get_first_node_in_group("main_camera")
	if not camera:
		# 查找任何Camera3D节点
		var cameras = get_tree().get_nodes_in_group("camera")
		if cameras.size() > 0:
			camera = cameras[0]

func _initialize_gesture_recognizer():
	gesture_recognizer = load("res://scripts/mobile_ui/gesture_recognizer.gd").new()
	add_child(gesture_recognizer)
	gesture_recognizer.gesture_detected.connect(_on_gesture_detected)

func _input(event):
	# 处理鼠标事件
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

	# 处理触摸事件
	if multi_touch_enabled:
		if event is InputEventScreenTouch:
			_handle_touch(event)
		elif event is InputEventScreenDrag:
			_handle_drag(event)

func _handle_mouse_button(event: InputEventMouseButton):
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_press_down(event.position)
		else:
			_handle_press_up(event.position)

func _handle_mouse_motion(event: InputEventMouseMotion):
	if is_dragging:
		_handle_drag_motion(event.relative, event.position)

func _handle_press_down(screen_pos: Vector2):
	var hit_result = _raycast_to_panel(screen_pos)

	if hit_result.has("panel_id"):
		current_panel_id = hit_result.panel_id
		is_dragging = true
		drag_start_position = hit_result.position

		# 发送按下事件
		var event_data = {
			"screen_position": screen_pos,
			"world_position": hit_result.position,
			"local_position": hit_result.local_position,
			"timestamp": Time.get_time_dict_from_system()
		}

		interaction_detected.emit(current_panel_id, "press_down", event_data)
		drag_started.emit(current_panel_id, drag_start_position)

		last_interaction_time = Time.get_ticks_msec() / 1000.0

func _handle_press_up(screen_pos: Vector2):
	if current_panel_id != "":
		var hit_result = _raycast_to_panel(screen_pos)

		# 判断是点击还是拖拽结束
		var current_time = Time.get_ticks_msec() / 1000.0
		var press_duration = current_time - last_interaction_time

		var event_data = {
			"screen_position": screen_pos,
			"world_position": hit_result.get("position", Vector3.ZERO),
			"local_position": hit_result.get("local_position", Vector2.ZERO),
			"duration": press_duration,
			"timestamp": Time.get_time_dict_from_system()
		}

		if is_dragging and drag_start_position.distance_to(hit_result.get("position", Vector3.ZERO)) > 0.01:
			# 拖拽结束
			interaction_detected.emit(current_panel_id, "drag_end", event_data)
			drag_ended.emit(current_panel_id, hit_result.get("position", Vector3.ZERO))
		else:
			# 点击事件
			interaction_detected.emit(current_panel_id, "click", event_data)

		current_panel_id = ""
		is_dragging = false

func _handle_drag_motion(relative: Vector2, screen_pos: Vector2):
	if current_panel_id != "":
		var hit_result = _raycast_to_panel(screen_pos)

		var event_data = {
			"screen_position": screen_pos,
			"world_position": hit_result.get("position", Vector3.ZERO),
			"local_position": hit_result.get("local_position", Vector2.ZERO),
			"relative_movement": relative,
			"delta": relative,
			"timestamp": Time.get_time_dict_from_system()
		}

		interaction_detected.emit(current_panel_id, "drag_move", event_data)

# 多指触摸处理
func _handle_touch(event: InputEventScreenTouch):
	var touch_id = event.index

	if event.pressed:
		touch_points[touch_id] = {
			"position": event.position,
			"start_time": Time.get_ticks_msec(),
			"panel": _get_panel_at_position(event.position)
		}
	else:
		if touch_points.has(touch_id):
			var touch_data = touch_points[touch_id]
			var duration = Time.get_ticks_msec() - touch_data.start_time

			# 处理触摸结束
			_process_touch_end(touch_id, event.position, duration)
			touch_points.erase(touch_id)

func _handle_drag(event: InputEventScreenDrag):
	var touch_id = event.index

	if touch_points.has(touch_id):
		var touch_data = touch_points[touch_id]
		var delta = event.relative

		# 更新触摸点位置
		touch_points[touch_id].position = event.position

		# 检查是否为多指手势
		if touch_points.size() > 1:
			_process_multi_touch_gesture()
		else:
			# 单指拖拽
			_process_single_touch_drag(touch_data, delta, event.position)

func _process_touch_end(touch_id: int, end_position: Vector2, duration: float):
	var touch_data = touch_points[touch_id]
	var start_pos = touch_data.position
	var distance = start_pos.distance_to(end_position)

	# 判断触摸类型
	if duration < 300 and distance < 10:  # 短按
		_handle_tap(touch_data, end_position)
	elif distance > 50:  # 滑动
		_handle_swipe(touch_data, end_position, distance)
	else:  # 长按
		_handle_long_press(touch_data, end_position, duration)

func _process_single_touch_drag(touch_data: Dictionary, delta: Vector2, current_pos: Vector2):
	if touch_data.panel:
		var event_data = {
			"touch_position": current_pos,
			"delta": delta,
			"panel_id": touch_data.panel,
			"timestamp": Time.get_time_dict_from_system()
		}

		interaction_detected.emit(touch_data.panel, "touch_drag", event_data)

func _process_multi_touch_gesture():
	var points = touch_points.values()
	if points.size() >= 2:
		var p1 = points[0].position
		var p2 = points[1].position

		# 计算手势参数
		var center = (p1 + p2) / 2
		var distance = p1.distance_to(p2)

		# 发送给手势识别器
		if gesture_recognizer:
			gesture_recognizer.update_multi_touch(points, center, distance)

func _handle_tap(touch_data: Dictionary, position: Vector2):
	if touch_data.panel:
		var event_data = {
			"touch_position": position,
			"panel_id": touch_data.panel,
			"tap_count": 1,
			"timestamp": Time.get_time_dict_from_system()
		}

		interaction_detected.emit(touch_data.panel, "tap", event_data)

func _handle_swipe(touch_data: Dictionary, end_position: Vector2, distance: float):
	if touch_data.panel:
		var start_pos = touch_data.position
		var direction = (end_position - start_pos).normalized()

		var event_data = {
			"start_position": start_pos,
			"end_position": end_position,
			"direction": direction,
			"distance": distance,
			"panel_id": touch_data.panel,
			"timestamp": Time.get_time_dict_from_system()
		}

		interaction_detected.emit(touch_data.panel, "swipe", event_data)

func _handle_long_press(touch_data: Dictionary, position: Vector2, duration: float):
	if touch_data.panel:
		var event_data = {
			"touch_position": position,
			"duration": duration,
			"panel_id": touch_data.panel,
			"timestamp": Time.get_time_dict_from_system()
		}

		interaction_detected.emit(touch_data.panel, "long_press", event_data)

func _get_panel_at_position(screen_pos: Vector2) -> String:
	var hit_result = _raycast_to_panel(screen_pos)
	return hit_result.get("panel_id", "")

# 通用输入事件处理
func process_input_event(panel_id: String, event: InputEvent, position: Vector3):
	var event_data = {
		"event_type": event.get_class(),
		"world_position": position,
		"timestamp": Time.get_time_dict_from_system()
	}

	# 根据事件类型添加额外数据
	if event is InputEventMouseButton:
		event_data["button_index"] = event.button_index
		event_data["pressed"] = event.pressed
		event_data["double_click"] = event.double_click
	elif event is InputEventMouseMotion:
		event_data["relative"] = event.relative
		event_data["velocity"] = event.velocity

	interaction_detected.emit(panel_id, "input_event", event_data)

# 射线检测
func _raycast_to_panel(screen_pos: Vector2) -> Dictionary:
	if not camera:
		return {}

	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * ray_length

	var space_state = get_viewport().world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collision_mask = interaction_layer

	var result = space_state.intersect_ray(query)
	if result:
		# 查找面板ID
		var collider = result.collider
		var panel_id = _find_panel_id_from_collider(collider)

		if panel_id != "":
			var ui_renderer = get_parent().get_node_or_null("UIRenderer3D")
			if ui_renderer:
				var local_pos = ui_renderer._calculate_local_position(
					result.position,
					collider.get_parent(),
					ui_renderer.panel_configs.get(panel_id, {})
				)

				return {
					"panel_id": panel_id,
					"position": result.position,
					"local_position": local_pos,
					"normal": result.normal,
					"collider": collider
				}

	return {}

func _find_panel_id_from_collider(collider: Node) -> String:
	# 从碰撞体向上查找面板ID
	var current = collider
	while current:
		if current.name == "InteractionArea":
			# 查找面板ID
			var ui_renderer = get_parent().get_node_or_null("UIRenderer3D")
			if ui_renderer:
				for panel_id in ui_renderer.sprites.keys():
					var sprite = ui_renderer.sprites[panel_id]
					if sprite.get_node_or_null("InteractionArea") == current:
						return panel_id
		current = current.get_parent()

	return ""

# 手势处理
func process_gesture(gesture_type: String, gesture_data: Dictionary):
	gesture_detected.emit(gesture_type, gesture_data)

func _on_gesture_detected(gesture_type: String, gesture_data: Dictionary):
	# 将手势事件转发给控制器
	if mobile_ui_controller:
		mobile_ui_controller._handle_gesture({
			"gesture_type": gesture_type,
			"gesture_data": gesture_data
		})

# 获取交互统计信息
func get_interaction_stats() -> Dictionary:
	return {
		"active_touches": touch_points.size(),
		"is_dragging": is_dragging,
		"current_panel": current_panel_id,
		"last_interaction_time": last_interaction_time,
		"gesture_recognizer_active": gesture_recognizer != null
	}

# 重置交互状态
func reset_interaction_state():
	current_panel_id = ""
	is_dragging = false
	touch_points.clear()
	last_interaction_time = 0.0

	if gesture_recognizer:
		gesture_recognizer.reset()
