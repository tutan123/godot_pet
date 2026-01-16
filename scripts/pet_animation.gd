extends Node

## pet_animation.gd
## 动画管理模块：负责 BlendTree 参数设置、程序化动画处理

const PetData = preload("res://scripts/pet_data.gd")

## 信号定义
signal anim_state_changed(old_state: int, new_state: int)
signal procedural_anim_changed(anim_type: int)
signal procedural_anim_finished(anim_name: String) # 新增：告知动作结束

## 节点引用（通过主控制器传递）
var animation_tree: AnimationTree
var mesh_root: Node3D
var skeleton: Skeleton3D  # 用于程序化骨骼动画
var anim_player: AnimationPlayer  # 直接访问 AnimationPlayer，用于播放非基础动画

## 状态变量（通过主控制器传递）
var current_anim_state: int = PetData.AnimState.IDLE
var proc_anim_type: int = PetData.ProcAnimType.NONE
var proc_time: float = 0.0
var tilt_angle: float = 0.0
var proc_rot_y: float = 0.0
var proc_rot_x: float = 0.0
var shake_intensity: float = 0.0
var current_action_state: Dictionary = {}

## 骨骼动画相关变量
var right_arm_bone_id: int = -1
var right_forearm_bone_id: int = -1
var right_arm_rest_transform: Transform3D
var right_forearm_rest_transform: Transform3D

## 设置动画状态
func set_anim_state(new_state: int, force: bool = false) -> void:
	if not force and current_anim_state == new_state:
		return
	
	if not animation_tree:
		return
	
	var prev_state = current_anim_state
	
	# 使用 BlendTree 参数驱动
	apply_blendtree_state(new_state)
	current_anim_state = new_state
	
	if prev_state != new_state:
		anim_state_changed.emit(prev_state, new_state)

## 强制设置动画状态
func force_anim_state(new_state: int) -> void:
	if not animation_tree:
		return
	
	apply_blendtree_state(new_state)
	current_anim_state = new_state

## 使用 BlendTree 参数驱动动画状态
func apply_blendtree_state(state: int) -> void:
	if not animation_tree:
		return
	
	if not animation_tree.active:
		animation_tree.active = true
	
	match state:
		PetData.AnimState.IDLE:
			animation_tree.set("parameters/locomotion/blend_position", 0.0)
			animation_tree.set("parameters/jump_blend/blend_amount", 0.0)
		PetData.AnimState.WALK:
			animation_tree.set("parameters/locomotion/blend_position", 0.3)
			animation_tree.set("parameters/jump_blend/blend_amount", 0.0)
		PetData.AnimState.RUN:
			animation_tree.set("parameters/locomotion/blend_position", 1.0)
			animation_tree.set("parameters/jump_blend/blend_amount", 0.0)
		PetData.AnimState.JUMP:
			animation_tree.set("parameters/jump_blend/blend_amount", 1.0)
		PetData.AnimState.WAVE:
			animation_tree.set("parameters/locomotion/blend_position", 0.0)
			animation_tree.set("parameters/jump_blend/blend_amount", 0.0)

## 切换动画（马尔可夫性：基于当前动作名称立即切换，无历史依赖）
func switch_anim(anim_name: String) -> void:
	var normalized_name = normalize_action_name(anim_name)
	
	# 检查是否是程序化动画
	if is_procedural_anim(normalized_name):
		# 马尔可夫性：立即设置程序化动画类型，基于当前动作名称
		if animation_tree:
			animation_tree.set("parameters/locomotion/blend_position", 0.0)
			animation_tree.set("parameters/jump_blend/blend_amount", 0.0)
		
		apply_blendtree_state(PetData.AnimState.IDLE)
		current_anim_state = PetData.AnimState.IDLE
		
		# 立即设置程序化动画类型（状态转换）
		set_procedural_anim(normalized_name)
		proc_time = 0.0  # 重置时间，让动画从0开始
		return
	
	# 切换回常规动画：清除程序化状态
	clear_procedural_anim_state()
	
	# 检查是否是基础移动动画（使用 BlendTree）
	var base_animations = ["idle", "stand", "walk", "run", "jump"]
	if normalized_name in base_animations:
		# 转换为枚举并立即切换（基于当前动作名称）
		var target_state = string_to_anim_state(normalized_name)
		set_anim_state(target_state, current_anim_state == PetData.AnimState.JUMP)
	else:
		# 其他动画：直接通过 AnimationPlayer 播放
		_play_animation_directly(normalized_name)

## 规范化动作名称
func normalize_action_name(name: String) -> String:
	var normalized = name.to_lower()
	match normalized:
		"backflip", "flip": return "flip"
		"shiver", "shake": return "shake"
		_: return normalized

## 判断是否为程序化动画
func is_procedural_anim(name: String) -> bool:
	return name in ["wave", "spin", "bounce", "fly", "roll", "shake", "flip", "dance"]

## 设置程序化动画
func set_procedural_anim(name: String) -> void:
	match name:
		"flip":
			proc_anim_type = PetData.ProcAnimType.FLIP
			proc_rot_x = 0.0
			proc_time = 0.0  # 重置时间，让FLIP动画从0开始
			# 核心修复：程序化期间暂时停用动画树，防止其强制重置骨骼坐标
			if animation_tree: animation_tree.active = false
		"wave":
			proc_anim_type = PetData.ProcAnimType.WAVE
			proc_time = 0.0  # 重置时间，让WAVE动画从0开始
			if animation_tree: animation_tree.active = false
		"spin":
			proc_anim_type = PetData.ProcAnimType.SPIN
			proc_rot_y = 0.0
		"bounce":
			proc_anim_type = PetData.ProcAnimType.BOUNCE
		"fly":
			proc_anim_type = PetData.ProcAnimType.FLY
			proc_time = 0.0  # 确保时间重置，让动画从头开始
		"roll":
			proc_anim_type = PetData.ProcAnimType.ROLL
		"shake":
			proc_anim_type = PetData.ProcAnimType.SHAKE
		"dance":
			proc_anim_type = PetData.ProcAnimType.DANCE
			proc_rot_y = 0.0
	
	procedural_anim_changed.emit(proc_anim_type)

## 清除程序化动画状态
func clear_procedural_anim_state() -> void:
	if proc_anim_type == PetData.ProcAnimType.WAVE or proc_anim_type == PetData.ProcAnimType.FLIP:
		_reset_arm_to_rest()
		# 恢复动画树控制
		if animation_tree: animation_tree.active = true
		
	if proc_anim_type == PetData.ProcAnimType.SPIN or proc_anim_type == PetData.ProcAnimType.DANCE:
		proc_rot_y = 0.0
	if proc_anim_type == PetData.ProcAnimType.FLIP:
		proc_rot_x = 0.0
	if proc_anim_type == PetData.ProcAnimType.FLY:
		# FLY 动画结束时，通知主控制器恢复物理状态
		var parent = get_parent()
		if parent and "is_flying" in parent:
			parent.is_flying = false
		procedural_anim_finished.emit("fly")
	
	var old_type = proc_anim_type
	proc_anim_type = PetData.ProcAnimType.NONE
	
	# 如果是其他带时长的动作，也发送完成信号
	if old_type == PetData.ProcAnimType.SPIN: procedural_anim_finished.emit("spin")
	elif old_type == PetData.ProcAnimType.FLIP: procedural_anim_finished.emit("flip")
	elif old_type == PetData.ProcAnimType.WAVE: procedural_anim_finished.emit("wave")
	
	procedural_anim_changed.emit(PetData.ProcAnimType.NONE)

## 应用程序化动画效果
func apply_procedural_fx(delta: float, is_dragging: bool) -> void:
	if not mesh_root:
		return
	
	proc_time += delta
	
	# 基础目标值
	var target_pos_y = 0.0
	var target_rot_x = tilt_angle
	var target_rot_z = 0.0
	var target_scale_y = 0.3
	
	# A. 基础呼吸感 (仅在 Idle 时)
	if current_anim_state == PetData.AnimState.IDLE:
		target_pos_y = sin(proc_time * 2.0) * 0.05
	
	# B. 根据当前活跃的程序化动作计算目标值
	match proc_anim_type:
		PetData.ProcAnimType.WAVE:
			# 整体摆动
			target_rot_z = sin(proc_time * 15.0) * 0.15
			target_scale_y = 0.3 * (1.0 + sin(proc_time * 10.0) * 0.05)
			# 右手挥舞
			_apply_arm_wave_animation(delta)
		PetData.ProcAnimType.SPIN:
			proc_rot_y += delta * 20.0
		PetData.ProcAnimType.BOUNCE:
			target_pos_y = abs(sin(proc_time * 10.0)) * 0.5
			target_scale_y = 0.3 * (1.0 - target_pos_y * 0.2)
		PetData.ProcAnimType.FLY:
			# FLY 动画：向上飞起并保持悬浮（持续时间更长）
			var fly_duration = 3.0  # 飞行持续时间（秒）
			if proc_time < fly_duration:
				# 前 0.5 秒：快速上升
				if proc_time < 0.5:
					var t = proc_time / 0.5
					target_pos_y = lerpf(0.0, 1.5, t * t)  # ease_out quadratic
				else:
					# 之后：悬浮并轻微上下摆动
					var hover_height = 1.5
					target_pos_y = hover_height + sin((proc_time - 0.5) * 2.0) * 0.2
				target_rot_x = 0.3
			else:
				# 飞行时间结束，逐渐下降
				var fall_t = (proc_time - fly_duration) / 0.5
				if fall_t < 1.0:
					target_pos_y = lerpf(1.5, 0.0, fall_t * fall_t)  # ease_in quadratic
				else:
					# 飞行完全结束，清除程序化动画状态（马尔可夫性：基于当前状态）
					clear_procedural_anim_state()
		PetData.ProcAnimType.ROLL:
			target_rot_z += delta * 15.0
		PetData.ProcAnimType.SHAKE:
			mesh_root.position.x = sin(proc_time * 25.0) * 0.1
			target_rot_z = sin(proc_time * 20.0) * 0.1
		PetData.ProcAnimType.FLIP:
			# 修复：使用 proc_time 而不是 current_action_state，支持场景执行
			var flip_duration = 2.0  # 固定2秒完成一次后空翻
			var t = clamp(proc_time / flip_duration, 0.0, 1.0)
			var flip_speed = TAU / flip_duration
			proc_rot_x = proc_time * flip_speed
			target_rot_x = proc_rot_x
			var jump_height = 0.6 * (4.0 * t * (1.0 - t))
			target_pos_y = jump_height
			if t > 0.15 and t < 0.85:
				target_rot_z = sin(proc_time * 10.0) * 0.08
			else:
				target_rot_z = 0.0
		PetData.ProcAnimType.DANCE:
			target_rot_z = sin(proc_time * 8.0) * 0.2
			target_pos_y = abs(sin(proc_time * 6.0)) * 0.3
			proc_rot_y += delta * 30.0
			target_scale_y = 0.3 * (1.0 + sin(proc_time * 4.0) * 0.1)
	
	# C. 拖拽时的特殊覆盖
	if is_dragging:
		target_rot_z = sin(proc_time * 10.0) * 0.2
	
	# D. 最终平滑应用到模型
	mesh_root.position.y = lerp(mesh_root.position.y, target_pos_y, 10.0 * delta)
	
	# X 轴旋转
	if proc_anim_type == PetData.ProcAnimType.FLIP:
		mesh_root.rotation.x = proc_rot_x
	else:
		mesh_root.rotation.x = lerp(mesh_root.rotation.x, target_rot_x, 10.0 * delta)
		proc_rot_x = lerp_angle(proc_rot_x, 0, 5.0 * delta)
	
	# Z 轴旋转
	if proc_anim_type not in [PetData.ProcAnimType.WAVE, PetData.ProcAnimType.ROLL, PetData.ProcAnimType.FLIP, PetData.ProcAnimType.DANCE] and not is_dragging:
		mesh_root.rotation.z = lerp(mesh_root.rotation.z, target_rot_z, 10.0 * delta)
	
	# Y 轴旋转
	if proc_anim_type == PetData.ProcAnimType.SPIN or proc_anim_type == PetData.ProcAnimType.DANCE:
		mesh_root.rotation.y = proc_rot_y
	else:
		proc_rot_y = lerp_angle(proc_rot_y, 0, 5.0 * delta)
		mesh_root.rotation.y = proc_rot_y
		
	mesh_root.scale.y = lerp(mesh_root.scale.y, target_scale_y, 10.0 * delta)
	
	# E. 点击后的抖动反馈
	if shake_intensity > 0:
		mesh_root.position.x = (randf() - 0.5) * shake_intensity * 0.2
		mesh_root.position.z = (randf() - 0.5) * shake_intensity * 0.2
		shake_intensity = move_toward(shake_intensity, 0, delta * 4.0)
	else:
		mesh_root.position.x = move_toward(mesh_root.position.x, 0, delta)
		mesh_root.position.z = move_toward(mesh_root.position.z, 0, delta)

## 工具函数
func anim_state_to_string(state: int) -> String:
	match state:
		PetData.AnimState.IDLE: return "idle"
		PetData.AnimState.WALK: return "walk"
		PetData.AnimState.RUN: return "run"
		PetData.AnimState.JUMP: return "jump"
		PetData.AnimState.WAVE: return "wave"
		_: return "idle"

func string_to_anim_state(name: String) -> int:
	var normalized = name.to_lower()
	match normalized:
		"idle": return PetData.AnimState.IDLE
		"walk": return PetData.AnimState.WALK
		"run": return PetData.AnimState.RUN
		"jump": return PetData.AnimState.JUMP
		"wave": return PetData.AnimState.WAVE
		_: return PetData.AnimState.IDLE

## 更新状态值（简化版：不再接收外部计时器，保护局部马尔可夫性）
func update_state_vars(anim_state: int, action_state: Dictionary) -> void:
	current_anim_state = anim_state
	current_action_state = action_state

## 获取状态值（供主控制器读取）
func get_state_vars() -> Dictionary:
	return {
		"proc_rot_y": proc_rot_y,
		"proc_rot_x": proc_rot_x,
		"proc_anim_type": proc_anim_type
	}

## 初始化骨骼引用（供主控制器调用）
func setup_skeleton(skeleton_node: Skeleton3D) -> void:
	skeleton = skeleton_node
	if not skeleton:
		return
	
	# 查找右手骨骼ID
	right_arm_bone_id = skeleton.find_bone("r-arm")
	right_forearm_bone_id = skeleton.find_bone("r-forearm")
	
	if right_arm_bone_id >= 0:
		right_arm_rest_transform = skeleton.get_bone_rest(right_arm_bone_id)
	if right_forearm_bone_id >= 0:
		right_forearm_rest_transform = skeleton.get_bone_rest(right_forearm_bone_id)

## 应用右手挥舞动画
func _apply_arm_wave_animation(_delta: float) -> void:
	if not skeleton or right_arm_bone_id < 0:
		return
	
	# 计算挥舞角度
	var wave_angle = sin(proc_time * 8.0) * 1.2
	var wave_forward = sin(proc_time * 8.0) * 0.3
	
	var rotation_transform = Transform3D()
	rotation_transform = rotation_transform.rotated(Vector3(1, 0, 0), wave_angle)
	rotation_transform = rotation_transform.rotated(Vector3(0, 0, 1), wave_forward * 0.5)
	
	var final_transform = right_arm_rest_transform * rotation_transform
	skeleton.set_bone_pose_position(right_arm_bone_id, final_transform.origin)
	skeleton.set_bone_pose_rotation(right_arm_bone_id, final_transform.basis.get_rotation_quaternion())
	
	if right_forearm_bone_id >= 0:
		var forearm_rotation = Transform3D()
		forearm_rotation = forearm_rotation.rotated(Vector3(1, 0, 0), wave_angle * 0.3)
		var forearm_final = right_forearm_rest_transform * forearm_rotation
		skeleton.set_bone_pose_position(right_forearm_bone_id, forearm_final.origin)
		skeleton.set_bone_pose_rotation(right_forearm_bone_id, forearm_final.basis.get_rotation_quaternion())

## 重置骨骼到休息姿态
func _reset_arm_to_rest() -> void:
	if not skeleton:
		return
	
	if right_arm_bone_id >= 0:
		skeleton.set_bone_pose_position(right_arm_bone_id, right_arm_rest_transform.origin)
		skeleton.set_bone_pose_rotation(right_arm_bone_id, right_arm_rest_transform.basis.get_rotation_quaternion())
	
	if right_forearm_bone_id >= 0:
		skeleton.set_bone_pose_position(right_forearm_bone_id, right_forearm_rest_transform.origin)
		skeleton.set_bone_pose_rotation(right_forearm_bone_id, right_forearm_rest_transform.basis.get_rotation_quaternion())

## 直接播放动画（不通过 AnimationTree）
## 用于播放非基础移动动画，无需在场景文件中定义
func _play_animation_directly(anim_name: String) -> void:
	if not anim_player:
		# 尝试从 mesh_root 获取 AnimationPlayer
		if mesh_root:
			anim_player = mesh_root.get_node_or_null("AnimationPlayer")
	
	if not anim_player:
		push_warning("[Animation] AnimationPlayer not found, cannot play: " + anim_name)
		return
	
	# 暂停 AnimationTree，让 AnimationPlayer 直接控制
	if animation_tree:
		animation_tree.active = false
	
	# 检查动画是否存在
	if not anim_player.has_animation(anim_name):
		push_warning("[Animation] Animation not found: " + anim_name)
		# 恢复 AnimationTree 并回到 idle
		if animation_tree:
			animation_tree.active = true
			set_anim_state(PetData.AnimState.IDLE)
		return
	
	# 播放动画
	anim_player.play(anim_name)
	
	# 如果动画不是循环的，等待完成后恢复 AnimationTree
	var anim = anim_player.get_animation(anim_name)
	if anim and anim.loop_mode != Animation.LOOP_LINEAR:
		# 使用协程等待动画完成
		_wait_for_animation_finish(anim_name)

## 等待动画完成的协程
func _wait_for_animation_finish(anim_name: String) -> void:
	if not anim_player:
		return
	
	# 等待动画播放完成
	await anim_player.animation_finished
	
	# 检查当前播放的动画是否是我们等待的动画
	if anim_player.current_animation == anim_name:
		# 恢复 AnimationTree 并回到 idle
		if animation_tree:
			animation_tree.active = true
			set_anim_state(PetData.AnimState.IDLE)
