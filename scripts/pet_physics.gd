extends Node

## pet_physics.gd
## 物理更新模块：负责物理计算、移动应用、碰撞处理
## 采用战术解耦设计，不侵入核心控制器逻辑

const PetData = preload("res://scripts/pet_data.gd")

## 信号定义
signal movement_calculated(movement_data)
signal jump_triggered(velocity_y: float)
signal collision_detected(collision_data: Dictionary)

## 配置参数（通过主控制器传递或外部加载）
var walk_speed: float = 3.0
var run_speed: float = 7.0
var rotation_speed: float = 12.0
var jump_velocity: float = 8.0
var push_force: float = 0.5
var gravity: float = 9.8

## 状态引用
var target_position: Vector3
var is_server_moving: bool = false
var is_flying: bool = false
var use_high_freq_sync: bool = false

# --- 战术状态变量 (内部维护，不侵入核心) ---
var _jump_push_pending: bool = false
var _jump_start_height: float = 0.0
var _jump_phase_2_threshold: float = 0.2 # 拔高 0.2 米再前冲
var _mid_air_push_speed: float = 5.0    # 空中前冲初速度

## 计算移动数据
func calculate_movement(input_data, current_position: Vector3, _delta: float):
	var movement = PetData.MovementData.new()
	
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
		
	elif is_server_moving:
		var to_target = (target_position - current_position)
		if not is_flying: to_target.y = 0
		if to_target.length() > 0.1:
			movement.direction = to_target.normalized()
			movement.speed = run_speed if not is_flying else run_speed * 1.2
			# 关键：根据速度决定动画状态
			movement.target_anim_state = PetData.AnimState.RUN if not is_flying else PetData.AnimState.WALK
			movement.tilt_target = 0.3 if is_flying else 0.1
		else:
			is_server_moving = false
			is_flying = false
			movement.target_anim_state = PetData.AnimState.IDLE
			
	else:
		movement.target_anim_state = PetData.AnimState.IDLE
	
	return movement

## 应用物理效果
func apply_physics(character_body: CharacterBody3D, delta: float) -> void:
	if is_flying: return
		
	# 保护向上跳跃的动量
	if not character_body.is_on_floor() or character_body.velocity.y > 0.1:
		character_body.velocity.y -= gravity * delta
	else:
		character_body.velocity.y = -0.1

## 执行空中战术动作 (核心解耦点)
## @param input_data: 当前输入数据，用于判断是否有用户输入
func process_tactical_logic(character_body: CharacterBody3D, input_data = null):
	# 如果有用户输入，不执行战术前冲，避免干扰用户控制
	if input_data and input_data.direction.length() > 0.1:
		return null

	if _jump_push_pending and not character_body.is_on_floor() and character_body.velocity.y > 0:
		var gain = character_body.global_position.y - _jump_start_height
		if gain > _jump_phase_2_threshold:
			var dir = (target_position - character_body.global_position).normalized()
			dir.y = 0
			if dir.length() > 0.1:
				character_body.velocity.x = dir.x * _mid_air_push_speed
				character_body.velocity.z = dir.z * _mid_air_push_speed
				_jump_push_pending = false
				return "Jump phase 2: Mid-air forward push at height +%.2f" % gain
	return null

## 启动跳跃战术
## with_push: 是否启用空中战术前冲（AI脱困时使用，手动跳跃不启用）
func execute_jump(character_body: CharacterBody3D, with_push: bool = false):
	character_body.velocity.y = jump_velocity
	_jump_push_pending = with_push 
	_jump_start_height = character_body.global_position.y
	jump_triggered.emit(jump_velocity)
	return "Jump phase 1: Vertical lift-off (v_y: %.1f)" % jump_velocity

## 应用移动速度
func apply_movement(movement_data, character_body: CharacterBody3D, delta: float) -> void:
	# 核心修复：移除上升期的 return 阻断，改为“叠加”或“保护”模式
	var is_jumping_up = character_body.velocity.y > 0.1
	
	if is_jumping_up:
		if _jump_push_pending:
			# 战术起跳第一阶段：暂时锁定水平速度，等待拔高
			return 
		else:
			# 跳跃过程中，允许水平惯性继续存在，并接受微弱修正
			var target_x = movement_data.direction.x * movement_data.speed
			var target_z = movement_data.direction.z * movement_data.speed
			if movement_data.direction.length() > 0.05:
				character_body.velocity.x = lerp(character_body.velocity.x, target_x, 2.0 * delta)
				character_body.velocity.z = lerp(character_body.velocity.z, target_z, 2.0 * delta)
			return

	# 常规地面移动逻辑
	if movement_data.direction.length() > 0.05:
		character_body.velocity.x = movement_data.direction.x * movement_data.speed
		character_body.velocity.z = movement_data.direction.z * movement_data.speed
	else:
		# 停止移动时，平滑减速而非瞬间归零（解决“跑两下就不动”的生硬感）
		character_body.velocity.x = lerp(character_body.velocity.x, 0.0, 10.0 * delta)
		character_body.velocity.z = lerp(character_body.velocity.z, 0.0, 10.0 * delta)
	
	# 朝向处理
	if movement_data.direction.length() > 0.1:
		var target_rotation = atan2(movement_data.direction.x, movement_data.direction.z)
		character_body.rotation.y = lerp_angle(character_body.rotation.y, target_rotation, rotation_speed * delta)

## 判定真实碰撞（过滤地板）
func check_real_collision(character_body: CharacterBody3D) -> bool:
	for i in range(character_body.get_slide_collision_count()):
		var coll = character_body.get_slide_collision(i)
		if coll.get_normal().y < 0.5: return true
	return false

# --- 原有兼容接口 ---
func handle_collisions(character_body: CharacterBody3D):
	if check_real_collision(character_body):
		var coll = character_body.get_last_slide_collision()
		collision_detected.emit({"collider_name": coll.get_collider().name})

func handle_physics_push(character_body: CharacterBody3D):
	for i in range(character_body.get_slide_collision_count()):
		var collision = character_body.get_slide_collision(i)
		var collider = collision.get_collider()
		if collider is RigidBody3D:
			var push_dir = -collision.get_normal()
			push_dir.y = 0
			collider.apply_impulse(push_dir * push_force, collision.get_position() - collider.global_position)

func handle_jump(input_data, character_body: CharacterBody3D) -> bool:
	if character_body.is_on_floor() and input_data.jump_just_pressed:
		execute_jump(character_body, false) # 手动跳跃不带空中推力
		return true
	return false
