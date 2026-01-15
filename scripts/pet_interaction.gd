extends Node

## pet_interaction.gd
## 交互处理模块：负责鼠标点击、拖拽等交互处理

const PetData = preload("res://scripts/pet_data.gd")

## 信号定义
signal interaction_sent(action: String, data: Dictionary)
signal drag_started()
signal drag_finished()
signal clicked()
signal ground_clicked(target_position: Vector3)  # 地面点击信号

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
					# 检查是否点击了地面
					var ground_pos = get_ground_position_under_mouse()
					if ground_pos:
						# 点击了地面，触发移动
						ground_clicked.emit(ground_pos)
						show_target_indicator(ground_pos)
					else:
						# 点击了角色或其他物体
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

## 获取鼠标下方的地面位置
func get_ground_position_under_mouse() -> Vector3:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return Vector3.ZERO
	
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	# 使用物理查询检测地面
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.collision_mask = 0xFFFFFFFF  # 检测所有层
	
	# 排除角色本身（通过查找CharacterBody3D）
	var exclude_list: Array[RID] = []
	var pet_node = get_tree().get_first_node_in_group("pet")
	if not pet_node:
		# 尝试通过名称查找
		pet_node = get_tree().get_root().find_child("Pet", true, false)
	if pet_node and pet_node is CharacterBody3D:
		exclude_list.append(pet_node.get_rid())
	query.exclude = exclude_list
	
	var result = space_state.intersect_ray(query)
	if result:
		# 检查是否点击了地面（通过碰撞体名称或类型判断）
		var collider = result.get("collider")
		if collider:
			var collider_name = collider.name.to_lower()
			# 如果点击的是Floor或地面相关的物体，返回位置
			if "floor" in collider_name or "ground" in collider_name or "plane" in collider_name:
				return result.get("position", Vector3.ZERO)
			# 如果是StaticBody3D且不是角色相关物体，也认为是地面
			if collider is StaticBody3D and "pet" not in collider_name and "player" not in collider_name:
				return result.get("position", Vector3.ZERO)
	
	return Vector3.ZERO

## 显示瞄准圆圈特效
func show_target_indicator(position: Vector3) -> void:
	# 创建瞄准圆圈（使用CSGCylinder或MeshInstance）
	var scene_root = get_tree().get_root().get_child(0)  # 获取主场景根节点
	
	# 创建圆圈节点
	var indicator = MeshInstance3D.new()
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 0.5
	cylinder_mesh.bottom_radius = 0.5
	cylinder_mesh.height = 0.01
	indicator.mesh = cylinder_mesh
	
	# 创建发光材质
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.8, 1.0, 0.8)  # 亮蓝色
	material.emission_enabled = true
	material.emission = Color(0.1, 0.4, 0.6, 1.0)
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.flags_transparent = true
	indicator.material_override = material
	
	# 设置位置（稍微高于地面）
	indicator.global_position = position + Vector3(0, 0.01, 0)
	indicator.rotation.x = deg_to_rad(90)  # 让圆柱体平躺
	
	scene_root.add_child(indicator)
	
	# 创建动画：淡入淡出并消失
	var tween = indicator.create_tween()
	tween.set_parallel(true)
	# 淡入
	tween.tween_property(indicator, "scale", Vector3(1.0, 1.0, 1.0), 0.1).from(Vector3(0.0, 0.0, 0.0))
	# 保持并淡出
	tween.tween_callback(func(): 
		var fade_tween = indicator.create_tween()
		fade_tween.tween_property(indicator, "scale", Vector3(0.0, 0.0, 0.0), 0.9).set_delay(0.1)
		fade_tween.tween_callback(func(): indicator.queue_free())
	).set_delay(1.0)
