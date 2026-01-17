extends Node

## pet_physics.gd
## 物理更新模块：负责物理计算、移动应用、碰撞处理

const PetData = preload("res://scripts/pet_data.gd")

## 信号定义
signal movement_calculated(movement_data)
signal jump_triggered(velocity_y: float)
signal collision_detected(collision_data: Dictionary)

## 配置参数（通过主控制器传递）
var walk_speed: float = 3.0
var run_speed: float = 7.0
var rotation_speed: float = 12.0
var jump_velocity: float = 6.5
var push_force: float = 0.5
var gravity: float = 9.8

## 状态引用（通过主控制器传递）
var target_position: Vector3
var is_server_moving: bool = false
var is_flying: bool = false  # 飞行模式：忽略 Y 轴约束
var use_high_freq_sync: bool = false
var server_target_pos: Vector3

## 计算移动数据
func calculate_movement(input_data, current_position: Vector3, _delta: float):
	var movement = PetData.MovementData.new()
	
	# 1. 本地输入移动
	if input_data.direction.length() > 0.1:
		is_server_moving = false
		use_high_freq_sync = false
		var camera = get_viewport().get_camera_3d()
		if camera:
			var cam_basis = camera.global_transform.basis
			movement.direction = (cam_basis.x * input_data.direction.x + cam_basis.z * input_data.direction.y).normalized()
			movement.direction.y = 0
		
		movement.is_running = input_data.is_running
		movement.speed = run_speed if movement.is_running else walk_speed
		movement.target_anim_state = PetData.AnimState.RUN if movement.is_running else PetData.AnimState.WALK
		movement.tilt_target = 0.2 if movement.is_running else 0.1
		
	# 2. 服务端指令移动
	elif is_server_moving:
		var to_target = (target_position - current_position)
		var dist_horizontal = Vector2(to_target.x, to_target.z).length()
		
		if not is_flying:
			to_target.y = 0 # 走路模式忽略 Y 轴差异
		
		var dist = to_target.length()
		if dist > 0.1:
			movement.direction = to_target.normalized()
			# 飞行速度稍微快一点，且确保有足够的水平分量
			movement.speed = run_speed * 1.2 if is_flying else walk_speed
			movement.target_anim_state = PetData.AnimState.WALK # 基础动画状态
			movement.tilt_target = 0.3 if is_flying else 0.1
		else:
			is_server_moving = false
			is_flying = false
			movement.target_anim_state = PetData.AnimState.IDLE
			movement.tilt_target = 0.0
			
	# 3. 高频同步（插值移动）
	elif use_high_freq_sync:
		movement.target_anim_state = PetData.AnimState.IDLE
		movement.tilt_target = 0.0
		
	# 4. 静止状态
	else:
		movement.target_anim_state = PetData.AnimState.IDLE
		movement.tilt_target = 0.0
	
	return movement

## 应用物理效果
func apply_physics(movement_data, character_body: CharacterBody3D, delta: float) -> void:
	if is_flying:
		return # 飞行模式不受重力影响
		
	if not character_body.is_on_floor():
		character_body.velocity.y -= gravity * delta
	else:
		var floor_normal = character_body.get_floor_normal()
		if movement_data.direction.length() < 0.1 and not is_server_moving and floor_normal.y < 0.99:
			var slide_gravity = Vector3(0, -gravity, 0).slide(floor_normal)
			character_body.velocity.x = lerp(character_body.velocity.x, slide_gravity.x, 2.0 * delta)
			character_body.velocity.z = lerp(character_body.velocity.z, slide_gravity.z, 2.0 * delta)
			character_body.velocity.y = slide_gravity.y
		else:
			character_body.velocity.y = -0.1

## 应用移动速度
func apply_movement(movement_data, character_body: CharacterBody3D, delta: float) -> float:
	if movement_data.direction.length() > 0.05:
		character_body.velocity.x = movement_data.direction.x * movement_data.speed
		character_body.velocity.z = movement_data.direction.z * movement_data.speed
		if is_flying:
			character_body.velocity.y = movement_data.direction.y * movement_data.speed
	else:
		character_body.velocity.x = 0
		character_body.velocity.z = 0
		if is_flying:
			character_body.velocity.y = 0
	
	# 朝向处理
	if movement_data.direction.length() > 0.1:
		var target_rotation = atan2(movement_data.direction.x, movement_data.direction.z)
		character_body.rotation.y = lerp_angle(character_body.rotation.y, target_rotation, rotation_speed * delta)
	
	return movement_data.tilt_target

## 处理跳跃
func handle_jump(input_data, character_body: CharacterBody3D) -> bool:
	if character_body.is_on_floor() and input_data.jump_just_pressed:
		character_body.velocity.y = jump_velocity
		jump_triggered.emit(character_body.velocity.y)
		return true
	return false

## 处理碰撞
func handle_collisions(character_body: CharacterBody3D) -> void:
	if character_body.get_slide_collision_count() == 0:
		return
	
	# 检查所有的碰撞，而不仅仅是最后一个，确保侧向擦碰也能触发
	for i in range(character_body.get_slide_collision_count()):
		var collision = character_body.get_slide_collision(i)
		var collider = collision.get_collider()
		var normal = collision.get_normal()
		
		# 优化判定：只要不是几乎垂直向下的支撑力（normal.y > 0.9），就认为是侧向或撞击碰撞
		if collider and normal.y < 0.9:
			collision_detected.emit({
				"collider_name": collider.name,
				"position": [collision.get_position().x, collision.get_position().y, collision.get_position().z],
				"normal": [normal.x, normal.y, normal.z]
			})
			# 找到一个有效碰撞就退出，防止单帧多次重复触发
			return

## 处理物理推力
func handle_physics_push(character_body: CharacterBody3D) -> void:
	for i in character_body.get_slide_collision_count():
		var collision = character_body.get_slide_collision(i)
		var collider = collision.get_collider()
		if collider is RigidBody3D:
			# 核心修复：只应用水平推力，防止垂直方向的反冲导致角色起飞
			var push_dir = -collision.get_normal()
			push_dir.y = 0 
			push_dir = push_dir.normalized()
			
			# 使用冲量推球，但限制强度
			collider.apply_central_impulse(push_dir * push_force)
			
			# 关键：如果角色被挤压向上，强制压制角色的垂直速度
			if character_body.velocity.y > 0 and collision.get_normal().y < 0.5:
				character_body.velocity.y *= 0.1
