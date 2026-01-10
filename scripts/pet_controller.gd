extends CharacterBody3D

## PetController.gd
## 增强版控制器：支持 Idle/Walk/Run、鼠标点击/拖拽交互、程序化动作及服务端同步。

## 动画状态枚举
enum AnimState {
	IDLE,
	WALK,
	RUN,
	JUMP,
	WAVE
}

## 程序化动画类型
enum ProcAnimType {
	NONE,
	WAVE,
	SPIN,
	BOUNCE,
	FLY,
	ROLL,
	SHAKE,
	FLIP
}

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")
@onready var ws_client = get_node_or_null("/root/Main/WebSocketClient")
@onready var mesh_root = $Player

@export_group("Movement Settings")
@export var walk_speed: float = 3.0
@export var run_speed: float = 7.0
@export var rotation_speed: float = 12.0
@export var jump_velocity: float = 6.5
@export var push_force: float = 0.5 # 显著减小推力，从 5.0 降到 0.5

@export_group("Interaction Settings")
@export var drag_height: float = 1.5

# 内部状态
var target_position: Vector3
var is_server_moving: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_anim_state: AnimState = AnimState.IDLE
var proc_anim_type: ProcAnimType = ProcAnimType.NONE

# 交互状态
var is_dragging: bool = false
var drag_start_mouse_pos: Vector2
var drag_threshold: float = 10.0 # 像素阈值，超过这个距离才算拖拽
var click_start_time: float = 0.0
var max_click_duration: float = 0.25 # 超过这个时间就不算点击

# 程序化动作变量
var proc_time: float = 0.0
var shake_intensity: float = 0.0
var tilt_angle: float = 0.0
var proc_rot_y: float = 0.0 # 专门用于 spin 的旋转累计值
var proc_rot_x: float = 0.0 # 专门用于 flip 的旋转累计值

# 状态声明式动作管理（参考网络游戏的状态同步模式）
var current_action_state: Dictionary = {} # {name, priority, duration, start_time, interruptible}
var action_queue: Array[Dictionary] = [] # 动作队列
var action_lock_time: float = 0.0 # 动作锁定到期时间

# 用于定时上报位置
var sync_timer: float = 0.0
var sync_interval: float = 1.0 # 每1秒同步一次位置到服务端
var last_jump_pressed: bool = false # 用于检测跳跃状态变化

# 用于服务端高频同步的插值缓冲
var server_target_pos: Vector3
var use_high_freq_sync: bool = false

func _ready() -> void:
	target_position = global_position
	server_target_pos = global_position
	if ws_client:
		ws_client.message_received.connect(_on_ws_message)
	
	animation_tree.active = true
	input_ray_pickable = true

func _input_event(camera: Camera3D, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
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
					# 结束拖拽
					is_dragging = false
					_send_interaction("drag_end", global_position)
					_on_drag_finished()
				elif click_start_time > 0 and duration < max_click_duration and mouse_move < drag_threshold:
					# 确认为单击
					_on_clicked()
				
				# 强制清空点击状态，彻底修复悬停起飞 Bug
				click_start_time = 0
				
	elif event is InputEventMouseMotion and click_start_time > 0:
		var mouse_move = (get_viewport().get_mouse_position() - drag_start_mouse_pos).length()
		if not is_dragging and mouse_move > drag_threshold:
			# 确认为拖拽开始
			is_dragging = true
			_send_interaction("drag_start", global_position)

func _on_drag_finished() -> void:
	# 姿态恢复逻辑
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh_root, "rotation:z", 0.0, 0.3)
	tween.tween_property(mesh_root, "position:x", 0.0, 0.3)
	tween.tween_property(mesh_root, "position:z", 0.0, 0.3)
	if proc_anim_type == ProcAnimType.NONE:
		tween.tween_property(mesh_root, "position:y", 0.0, 0.3)

func _physics_process(delta: float) -> void:
	proc_time += delta
	
	# 1. 前置检查和更新
	_update_action_state_expiry()
	_update_state_sync(delta)
	
	# 2. 拖拽处理（最高优先级）
	if is_dragging:
		_handle_dragging(delta)
		return
	
	# 3. 输入和状态检测
	var input_data = _get_input_data()
	var movement_data = _calculate_movement(input_data, delta)
	
	# 4. 应用物理和移动
	_apply_physics(movement_data, delta)
	_apply_movement(movement_data, delta)
	_handle_jump(input_data)
	
	move_and_slide()
	
	# 5. 落地后状态修正（必须在 move_and_slide 之后）
	_handle_landing_state_fix(input_data, movement_data)
	
	# 6. 碰撞和物理交互
	_handle_collisions()
	_handle_physics_push()

func _process(delta: float) -> void:
	# 8. 应用程序化动画 (叠加效果)
	# 在 _process 中执行以覆盖骨骼动画的渲染位置
	_apply_procedural_fx(delta)

func _handle_dragging(delta: float) -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var drop_plane = Plane(Vector3.UP, drag_height)
	var intersect_pos = drop_plane.intersects_ray(ray_origin, ray_dir)
	
	if intersect_pos:
		global_position = global_position.lerp(intersect_pos, 20.0 * delta)
		velocity = Vector3.ZERO
		_switch_anim("jump")
		# 拖拽时的程序化摆动
		mesh_root.rotation.z = sin(proc_time * 10.0) * 0.2

func _on_clicked() -> void:
	_send_interaction("click", global_position)
	# 本地立即反馈：缩小一下再弹起
	var tween = create_tween()
	tween.tween_property(mesh_root, "scale", Vector3(1.2, 0.8, 1.2) * 0.3, 0.1)
	tween.tween_property(mesh_root, "scale", Vector3(1.0, 1.0, 1.0) * 0.3, 0.2).set_trans(Tween.TRANS_BOUNCE)

func _apply_procedural_fx(delta: float) -> void:
	# 基础目标值
	var target_pos_y = 0.0
	var target_rot_x = tilt_angle
	var target_rot_z = 0.0
	var target_scale_y = 0.3
	
	# A. 基础呼吸感 (仅在 Idle 时)
	if current_anim_state == AnimState.IDLE:
		target_pos_y = sin(proc_time * 2.0) * 0.05
	
	# B. 根据当前活跃的程序化动作计算目标值
	match proc_anim_type:
		ProcAnimType.WAVE:
			target_rot_z = sin(proc_time * 15.0) * 0.15
			target_scale_y = 0.3 * (1.0 + sin(proc_time * 10.0) * 0.05)
		ProcAnimType.SPIN:
			proc_rot_y += delta * 20.0 # 持续增加旋转
		ProcAnimType.BOUNCE:
			target_pos_y = abs(sin(proc_time * 10.0)) * 0.5
			target_scale_y = 0.3 * (1.0 - target_pos_y * 0.2)
		ProcAnimType.FLY:
			target_pos_y = 1.0 + sin(proc_time * 3.0) * 0.2
			target_rot_x = 0.3
		ProcAnimType.ROLL:
			target_rot_z += delta * 15.0 # 持续增加
		ProcAnimType.SHAKE:
			mesh_root.position.x = sin(proc_time * 25.0) * 0.1
			target_rot_z = sin(proc_time * 20.0) * 0.1
		ProcAnimType.FLIP:
			# 后空翻：基于动作状态的完整翻转，而不是持续弹跳
			# 使用 current_action_state 的开始时间来计算已用时间
			var action_start_time = current_action_state.get("start_time", 0.0)
			if action_start_time > 0.0:
				# 计算动作已用时间（秒）
				var flip_elapsed = Time.get_unix_time_from_system() - action_start_time
				var flip_duration = current_action_state.get("duration", 2000) / 1000.0 # 转换为秒
				
				# 归一化时间 0-1，限制在动作持续时间内
				var t = clamp(flip_elapsed / flip_duration, 0.0, 1.0)
				
				# 翻转：在动作时间内完成一个完整的后空翻（360度）
				# 使用线性旋转，2秒内完成一圈
				var flip_speed = TAU / flip_duration # 根据 duration 调整速度
				proc_rot_x = flip_elapsed * flip_speed
				target_rot_x = proc_rot_x
				
				# 弹跳轨迹：抛物线，在中间（t=0.5）达到最高点，然后落下
				# 使用抛物线公式：h = 4 * t * (1 - t)，在 t=0.5 时达到最高点 1.0
				var jump_height = 0.6 * (4.0 * t * (1.0 - t)) # 最高 0.6 单位（降低高度）
				target_pos_y = jump_height
				
				# 轻微的 Z 轴摆动（只在空中时，增加动感）
				if t > 0.15 and t < 0.85:
					target_rot_z = sin(flip_elapsed * 10.0) * 0.08
				else:
					target_rot_z = 0.0
			else:
				# 如果还没有 start_time，初始化
				proc_rot_x = 0.0
				target_pos_y = 0.0
				target_rot_x = 0.0
	
	# C. 拖拽时的特殊覆盖
	if is_dragging:
		target_rot_z = sin(proc_time * 10.0) * 0.2
	
	# D. 最终平滑应用到模型 (除了自增量)
	mesh_root.position.y = lerp(mesh_root.position.y, target_pos_y, 10.0 * delta)
	
	# X 轴旋转：flip 使用累加旋转，其他动作平滑应用或回归
	if proc_anim_type == ProcAnimType.FLIP:
		mesh_root.rotation.x = proc_rot_x # 直接应用累加的旋转角度
	else:
		mesh_root.rotation.x = lerp(mesh_root.rotation.x, target_rot_x, 10.0 * delta)
		proc_rot_x = lerp_angle(proc_rot_x, 0, 5.0 * delta) # 平滑回归 0
	
	# 只有在非特殊旋转动作时才重置 Z 轴（平滑回归 0）
	if proc_anim_type not in [ProcAnimType.WAVE, ProcAnimType.ROLL, ProcAnimType.FLIP] and not is_dragging:
		mesh_root.rotation.z = lerp(mesh_root.rotation.z, target_rot_z, 10.0 * delta)
	
	# Y 轴旋转：spin 使用累加旋转，其他动作平滑回归 0
	if proc_anim_type == ProcAnimType.SPIN:
		mesh_root.rotation.y = proc_rot_y
	else:
		proc_rot_y = lerp_angle(proc_rot_y, 0, 5.0 * delta)
		mesh_root.rotation.y = proc_rot_y
		
	mesh_root.scale.y = lerp(mesh_root.scale.y, target_scale_y, 10.0 * delta)
	
	# E. 点击后的抖动反馈 (独立叠加)
	if shake_intensity > 0:
		mesh_root.position.x = (randf() - 0.5) * shake_intensity * 0.2
		mesh_root.position.z = (randf() - 0.5) * shake_intensity * 0.2
		shake_intensity = move_toward(shake_intensity, 0, delta * 4.0)
	else:
		mesh_root.position.x = move_toward(mesh_root.position.x, 0, delta)
		mesh_root.position.z = move_toward(mesh_root.position.z, 0, delta)

## 辅助数据结构
class MovementData:
	var direction: Vector3
	var speed: float
	var is_running: bool
	var target_anim_state: AnimState
	var tilt_target: float
	
	func _init():
		direction = Vector3.ZERO
		speed = 0.0
		is_running = false
		target_anim_state = AnimState.IDLE
		tilt_target = 0.0

class InputData:
	var direction: Vector2
	var is_running: bool
	var is_typing: bool
	var jump_pressed: bool
	var jump_just_pressed: bool
	
	func _init():
		direction = Vector2.ZERO
		is_running = false
		is_typing = false
		jump_pressed = false
		jump_just_pressed = false

## 状态管理和更新方法
func _update_action_state_expiry() -> void:
	if current_action_state.is_empty():
		return
	
	var elapsed = (Time.get_unix_time_from_system() - current_action_state.get("start_time", 0.0)) * 1000.0
	var duration = current_action_state.get("duration", 3000)
	
	if elapsed >= duration:
		var action_name = current_action_state.get("name", "idle")
		_clear_procedural_anim(action_name)
		current_action_state = {}
		action_lock_time = 0.0

func _update_state_sync(delta: float) -> void:
	sync_timer += delta
	if sync_timer >= sync_interval:
		_send_state_sync()
		sync_timer = 0.0

func _get_input_data() -> InputData:
	var data = InputData.new()
	var focus_owner = get_viewport().gui_get_focus_owner()
	data.is_typing = focus_owner is LineEdit
	
	if not data.is_typing:
		data.direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		data.is_running = Input.is_key_pressed(KEY_SHIFT)
		data.jump_pressed = Input.is_action_pressed("jump")
		data.jump_just_pressed = Input.is_action_just_pressed("jump")
	
	return data

func _calculate_movement(input_data: InputData, delta: float) -> MovementData:
	var movement = MovementData.new()
	
	# 本地输入移动
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
		movement.target_anim_state = AnimState.RUN if movement.is_running else AnimState.WALK
		movement.tilt_target = 0.2 if movement.is_running else 0.1
		
	# 服务端移动
	elif is_server_moving:
		var to_target = (target_position - global_position)
		to_target.y = 0
		if to_target.length() > 0.25:
			movement.direction = to_target.normalized()
			movement.speed = walk_speed
			movement.target_anim_state = AnimState.WALK
			movement.tilt_target = 0.1
		else:
			is_server_moving = false
			movement.target_anim_state = AnimState.IDLE
			movement.tilt_target = 0.0
			
	# 高频同步（插值移动）
	elif use_high_freq_sync:
		global_position = global_position.lerp(server_target_pos, 0.2)
		movement.target_anim_state = AnimState.IDLE
		movement.tilt_target = 0.0
		
	# 静止状态
	else:
		movement.target_anim_state = AnimState.IDLE
		movement.tilt_target = 0.0
	
	return movement

func _apply_physics(movement_data: MovementData, delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		var floor_normal = get_floor_normal()
		if movement_data.direction.length() < 0.1 and not is_server_moving and floor_normal.y < 0.99:
			var slide_gravity = Vector3(0, -gravity, 0).slide(floor_normal)
			velocity.x = lerp(velocity.x, slide_gravity.x, 2.0 * delta)
			velocity.z = lerp(velocity.z, slide_gravity.z, 2.0 * delta)
			velocity.y = slide_gravity.y
		else:
			velocity.y = -0.1

func _apply_movement(movement_data: MovementData, delta: float) -> void:
	if movement_data.direction.length() > 0.1:
		velocity.x = movement_data.direction.x * movement_data.speed
		velocity.z = movement_data.direction.z * movement_data.speed
	else:
		velocity.x = move_toward(velocity.x, 0, walk_speed * delta * 10)
		velocity.z = move_toward(velocity.z, 0, walk_speed * delta * 10)
	
	# 朝向处理
	if movement_data.direction.length() > 0.1:
		var target_rotation = atan2(movement_data.direction.x, movement_data.direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)
	elif velocity.length() > 0.5:
		var move_dir = Vector3(velocity.x, 0, velocity.z).normalized()
		if move_dir.length() > 0.1:
			var target_rotation = atan2(move_dir.x, move_dir.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * 0.5 * delta)
	
	# 倾斜角度平滑
	tilt_angle = lerp(tilt_angle, movement_data.tilt_target, 5.0 * delta)
	
	# 动画状态切换
	if current_action_state.is_empty():
		_set_anim_state(movement_data.target_anim_state)

func _handle_jump(input_data: InputData) -> void:
	if is_on_floor() and input_data.jump_just_pressed:
		velocity.y = jump_velocity
		_set_anim_state(AnimState.JUMP)
		if ws_client and ws_client.is_connected:
			ws_client.send_message("interaction", {
				"action": "jump",
				"position": [global_position.x, global_position.y, global_position.z],
				"velocity_y": velocity.y
			})
	last_jump_pressed = input_data.jump_pressed

func _handle_landing_state_fix(input_data: InputData, movement_data: MovementData) -> void:
	if not (is_on_floor() and playback):
		return
	
	var current_playing = playback.get_current_node()
	var is_jump_state = current_playing == "jump" or current_anim_state == AnimState.JUMP
	
	if is_jump_state:
		# 落地后根据输入决定目标状态
		var target_state: AnimState
		if input_data.direction.length() > 0.1:
			target_state = AnimState.RUN if input_data.is_running else AnimState.WALK
		else:
			target_state = AnimState.IDLE
		
		_force_anim_state(target_state)
		print("[Pet] Forced animation switch after landing: %s -> %s" % [current_playing, _anim_state_to_string(target_state)])
	elif current_action_state.is_empty() and input_data.direction.length() < 0.1:
		if current_anim_state != AnimState.IDLE:
			_set_anim_state(AnimState.IDLE)

func _handle_collisions() -> void:
	if get_slide_collision_count() == 0:
		return
	
	var collision = get_last_slide_collision()
	var collider = collision.get_collider()
	var normal = collision.get_normal()
	
	# 智能过滤：如果碰撞法线主要向上 (Y > 0.7)，说明是踩在物体上，不是撞到物体
	if collider and normal.y < 0.7:
		_send_interaction("collision", {
			"collider_name": collider.name,
			"position": [collision.get_position().x, collision.get_position().y, collision.get_position().z],
			"normal": [normal.x, normal.y, normal.z]
		})

func _handle_physics_push() -> void:
	# 物理推力处理：让机器人能推球
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider is RigidBody3D:
			var push_dir = -collision.get_normal()
			push_dir.y = 0
			collider.apply_central_impulse(push_dir * push_force)

## 动画状态管理（重构后的优雅版本）
func _set_anim_state(new_state: AnimState, force: bool = false) -> void:
	if not force and current_anim_state == new_state:
		return
	
	if not playback:
		return
	
	var state_name = _anim_state_to_string(new_state)
	var prev_state = current_anim_state
	var current_playing = playback.get_current_node()
	
	# 强制切换（特别是从jump状态切换时）
	playback.travel(state_name)
	current_anim_state = new_state
	
	if prev_state != new_state:
		print("[Pet] Animation state: %s -> %s (was playing: %s)" % [_anim_state_to_string(prev_state), state_name, current_playing])

func _force_anim_state(new_state: AnimState) -> void:
	if not playback:
		return
	
	var state_name = _anim_state_to_string(new_state)
	playback.travel(state_name)
	current_anim_state = new_state

func _anim_state_to_string(state: AnimState) -> String:
	match state:
		AnimState.IDLE: return "idle"
		AnimState.WALK: return "walk"
		AnimState.RUN: return "run"
		AnimState.JUMP: return "jump"
		AnimState.WAVE: return "wave"
		_: return "idle"

func _string_to_anim_state(name: String) -> AnimState:
	var normalized = name.to_lower()
	match normalized:
		"idle": return AnimState.IDLE
		"walk": return AnimState.WALK
		"run": return AnimState.RUN
		"jump": return AnimState.JUMP
		"wave": return AnimState.WAVE
		_: return AnimState.IDLE

func _clear_procedural_anim(action_name: String) -> void:
	match action_name:
		"spin":
			proc_rot_y = 0.0
		"flip":
			proc_rot_x = 0.0
	proc_anim_type = ProcAnimType.NONE

func _switch_anim(anim_name: String) -> void:
	# 动作名称映射和规范化
	var normalized_name = _normalize_action_name(anim_name)
	
	# 检查是否是程序化动画
	if _is_procedural_anim(normalized_name):
		_set_procedural_anim(normalized_name)
		return
	
	# 切换回常规动画
	_clear_procedural_anim_state()
	
	# 转换为枚举并切换
	var target_state = _string_to_anim_state(normalized_name)
	_set_anim_state(target_state, current_anim_state == AnimState.JUMP)

func _normalize_action_name(name: String) -> String:
	var normalized = name.to_lower()
	match normalized:
		"backflip", "flip": return "flip"
		"shiver", "shake": return "shake"
		_: return normalized

func _is_procedural_anim(name: String) -> bool:
	return name in ["wave", "spin", "bounce", "fly", "roll", "shake", "flip"]

func _set_procedural_anim(name: String) -> void:
	match name:
		"flip":
			proc_anim_type = ProcAnimType.FLIP
			proc_rot_x = 0.0
		"spin":
			proc_anim_type = ProcAnimType.SPIN
			proc_rot_y = 0.0
		"wave":
			proc_anim_type = ProcAnimType.WAVE
		"bounce":
			proc_anim_type = ProcAnimType.BOUNCE
		"fly":
			proc_anim_type = ProcAnimType.FLY
		"roll":
			proc_anim_type = ProcAnimType.ROLL
		"shake":
			proc_anim_type = ProcAnimType.SHAKE
	
	if playback:
		playback.travel("idle")  # 程序化动画时保持基础姿态
	print("[Pet] Switched to procedural animation: %s" % name)

func _clear_procedural_anim_state() -> void:
	if proc_anim_type == ProcAnimType.SPIN:
		proc_rot_y = 0.0
	if proc_anim_type == ProcAnimType.FLIP:
		proc_rot_x = 0.0
	proc_anim_type = ProcAnimType.NONE

func _send_interaction(action: String, extra_data: Variant) -> void:
	if ws_client and ws_client.is_connected:
		var data = {
			"action": action
		}
		
		if extra_data is Vector3:
			data["position"] = [extra_data.x, extra_data.y, extra_data.z]
		elif extra_data is Dictionary:
			for key in extra_data.keys():
				data[key] = extra_data[key]
				
		ws_client.send_message("interaction", data)

func _send_state_sync() -> void:
	if ws_client and ws_client.is_connected:
		# 获取当前键盘输入状态，用于点亮行为树
		var focus_owner = get_viewport().gui_get_focus_owner()
		var is_typing = focus_owner is LineEdit
		var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var is_moving_locally = input_dir.length() > 0.1 and not is_typing
		var is_jump_pressed = Input.is_action_pressed("jump") and not is_typing
		
		ws_client.send_message("state_sync", {
			"position": [global_position.x, global_position.y, global_position.z],
			"current_action": _anim_state_to_string(current_anim_state),
			"is_dragging": is_dragging,
			"is_on_floor": is_on_floor(),
			"is_moving_locally": is_moving_locally,
			"is_jump_pressed": is_jump_pressed,
			"velocity": [velocity.x, velocity.y, velocity.z]
		})

func _on_ws_message(type: String, data: Dictionary) -> void:
	# print("Received message: ", type, data)
	match type:
		"bt_output":
			# 优先使用状态声明式协议 (actionState)
			if data.has("actionState"):
				var action_state = data["actionState"]
				_apply_action_state(action_state)
			# 向后兼容：直接 action 字段
			elif data.has("action"):
				var action_name = data["action"].to_lower()
				# 转换为状态格式
				_apply_action_state({
					"name": action_name,
					"priority": 50,
					"duration": 3000,
					"interruptible": true,
					"timestamp": Time.get_unix_time_from_system()
				})
		"move_to":
			if data.has("target"):
				var t = data["target"]
				target_position = Vector3(t[0], t[1], t[2])
				is_server_moving = true
		"set_position":
			if data.has("pos"):
				var p = data["pos"]
				server_target_pos = Vector3(p[0], p[1], p[2])
				use_high_freq_sync = true
				is_server_moving = false

# 状态声明式动作管理：参考网络游戏的状态同步模式
func _apply_action_state(action_state: Dictionary) -> void:
	var action_name = action_state.get("name", "idle").to_lower()
	var priority = action_state.get("priority", 50)
	var duration_ms = action_state.get("duration", 3000)
	var interruptible = action_state.get("interruptible", true)
	var timestamp = action_state.get("timestamp", Time.get_unix_time_from_system())
	
	# 检查优先级和中断规则
	var current_priority = current_action_state.get("priority", 0)
	var current_duration = current_action_state.get("duration", 0)
	var current_start_time = current_action_state.get("start_time", 0.0)
	var current_interruptible = current_action_state.get("interruptible", true)
	var elapsed = (Time.get_unix_time_from_system() - current_start_time) * 1000.0
	
	# 判断是否应该中断当前动作
	var should_interrupt = false
	if current_action_state.is_empty():
		should_interrupt = true
	elif priority > current_priority:
		# 高优先级可以中断低优先级
		should_interrupt = true
	elif interruptible and current_interruptible:
		# 两个都可中断，按优先级
		if priority >= current_priority:
			should_interrupt = true
	elif elapsed >= current_duration:
		# 当前动作已完成
		should_interrupt = true
	
	if should_interrupt:
		current_action_state = {
			"name": action_name,
			"priority": priority,
			"duration": duration_ms,
			"interruptible": interruptible,
			"start_time": Time.get_unix_time_from_system(),
			"timestamp": timestamp
		}
		action_lock_time = Time.get_unix_time_from_system() + (duration_ms / 1000.0)
		_switch_anim(action_name)
		print("[Pet] Applied action state: %s (priority: %d, duration: %dms, interruptible: %s)" % [action_name, priority, duration_ms, interruptible])
