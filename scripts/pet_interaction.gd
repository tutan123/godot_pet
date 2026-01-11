extends Node

## pet_interaction.gd
## 交互处理模块：负责鼠标点击、拖拽等交互处理

const PetData = preload("res://scripts/pet_data.gd")

## 信号定义
signal interaction_sent(action: String, data: Dictionary)
signal drag_started()
signal drag_finished()
signal clicked()

## 配置参数
var drag_height: float = 1.5
var drag_threshold: float = 10.0
var max_click_duration: float = 0.25

## 状态变量
var is_dragging: bool = false
var drag_start_mouse_pos: Vector2
var click_start_time: float = 0.0

## 处理输入事件
func handle_input_event(event: InputEvent, character_body: CharacterBody3D, mesh_root: Node3D, _proc_time: float, proc_anim_type: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				click_start_time = Time.get_unix_time_from_system()
				drag_start_mouse_pos = get_viewport().get_mouse_position()
				is_dragging = false
			else:
				var duration = Time.get_unix_time_from_system() - click_start_time
				var mouse_move = (get_viewport().get_mouse_position() - drag_start_mouse_pos).length()
				
				if is_dragging:
					is_dragging = false
					interaction_sent.emit("drag_end", {"position": [character_body.global_position.x, character_body.global_position.y, character_body.global_position.z]})
					drag_finished.emit()
					on_drag_finished(mesh_root, proc_anim_type)
				elif click_start_time > 0 and duration < max_click_duration and mouse_move < drag_threshold:
					clicked.emit()
					interaction_sent.emit("click", {"position": [character_body.global_position.x, character_body.global_position.y, character_body.global_position.z]})
					on_clicked(mesh_root)
				
				click_start_time = 0
				
	elif event is InputEventMouseMotion and click_start_time > 0:
		var mouse_move = (get_viewport().get_mouse_position() - drag_start_mouse_pos).length()
		if not is_dragging and mouse_move > drag_threshold:
			is_dragging = true
			interaction_sent.emit("drag_start", {"position": [character_body.global_position.x, character_body.global_position.y, character_body.global_position.z]})
			drag_started.emit()

## 处理拖拽
func handle_dragging(delta: float, character_body: CharacterBody3D, mesh_root: Node3D, proc_time: float) -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var drop_plane = Plane(Vector3.UP, drag_height)
	var intersect_pos = drop_plane.intersects_ray(ray_origin, ray_dir)
	
	if intersect_pos:
		character_body.global_position = character_body.global_position.lerp(intersect_pos, 20.0 * delta)
		character_body.velocity = Vector3.ZERO
		# 拖拽时的程序化摆动
		mesh_root.rotation.z = sin(proc_time * 10.0) * 0.2

## 点击处理
func on_clicked(mesh_root: Node3D) -> void:
	# 本地立即反馈：缩小一下再弹起
	var tween = mesh_root.create_tween()
	tween.tween_property(mesh_root, "scale", Vector3(1.2, 0.8, 1.2) * 0.3, 0.1)
	tween.tween_property(mesh_root, "scale", Vector3(1.0, 1.0, 1.0) * 0.3, 0.2).set_trans(Tween.TRANS_BOUNCE)

## 拖拽结束处理
func on_drag_finished(mesh_root: Node3D, proc_anim_type: int) -> void:
	# 姿态恢复逻辑
	var tween = mesh_root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh_root, "rotation:z", 0.0, 0.3)
	tween.tween_property(mesh_root, "position:x", 0.0, 0.3)
	tween.tween_property(mesh_root, "position:z", 0.0, 0.3)
	if proc_anim_type == PetData.ProcAnimType.NONE:
		tween.tween_property(mesh_root, "position:y", 0.0, 0.3)
