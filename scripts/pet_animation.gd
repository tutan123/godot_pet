extends Node

## pet_animation.gd
## 动画管理模块：负责 BlendTree 参数设置、程序化动画处理

const PetData = preload("res://scripts/pet_data.gd")

## 信号定义
signal anim_state_changed(old_state: int, new_state: int)
signal procedural_anim_changed(anim_type: int)

## 节点引用（通过主控制器传递）
var animation_tree: AnimationTree
var mesh_root: Node3D

## 状态变量（通过主控制器传递）
var current_anim_state: int = PetData.AnimState.IDLE
var proc_anim_type: int = PetData.ProcAnimType.NONE
var proc_time: float = 0.0
var tilt_angle: float = 0.0
var proc_rot_y: float = 0.0
var proc_rot_x: float = 0.0
var shake_intensity: float = 0.0
var current_action_state: Dictionary = {}

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

## 切换动画
func switch_anim(anim_name: String) -> void:
	var normalized_name = normalize_action_name(anim_name)
	
	# 检查是否是程序化动画
	if is_procedural_anim(normalized_name):
		set_procedural_anim(normalized_name)
		return
	
	# 切换回常规动画
	clear_procedural_anim_state()
	
	# 转换为枚举并切换
	var target_state = string_to_anim_state(normalized_name)
	set_anim_state(target_state, current_anim_state == PetData.AnimState.JUMP)

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
		"spin":
			proc_anim_type = PetData.ProcAnimType.SPIN
			proc_rot_y = 0.0
		"wave":
			proc_anim_type = PetData.ProcAnimType.WAVE
		"bounce":
			proc_anim_type = PetData.ProcAnimType.BOUNCE
		"fly":
			proc_anim_type = PetData.ProcAnimType.FLY
		"roll":
			proc_anim_type = PetData.ProcAnimType.ROLL
		"shake":
			proc_anim_type = PetData.ProcAnimType.SHAKE
		"dance":
			proc_anim_type = PetData.ProcAnimType.DANCE
			proc_rot_y = 0.0
	
	# 程序化动画时保持基础姿态（idle）
	if animation_tree:
		animation_tree.set("parameters/locomotion/blend_position", 0.0)
	
	procedural_anim_changed.emit(proc_anim_type)

## 清除程序化动画
func clear_procedural_anim(action_name: String) -> void:
	match action_name:
		"spin":
			proc_rot_y = 0.0
		"flip":
			proc_rot_x = 0.0
	proc_anim_type = PetData.ProcAnimType.NONE
	procedural_anim_changed.emit(PetData.ProcAnimType.NONE)

## 清除程序化动画状态
func clear_procedural_anim_state() -> void:
	if proc_anim_type == PetData.ProcAnimType.SPIN or proc_anim_type == PetData.ProcAnimType.DANCE:
		proc_rot_y = 0.0
	if proc_anim_type == PetData.ProcAnimType.FLIP:
		proc_rot_x = 0.0
	proc_anim_type = PetData.ProcAnimType.NONE
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
			target_rot_z = sin(proc_time * 15.0) * 0.15
			target_scale_y = 0.3 * (1.0 + sin(proc_time * 10.0) * 0.05)
		PetData.ProcAnimType.SPIN:
			proc_rot_y += delta * 20.0
		PetData.ProcAnimType.BOUNCE:
			target_pos_y = abs(sin(proc_time * 10.0)) * 0.5
			target_scale_y = 0.3 * (1.0 - target_pos_y * 0.2)
		PetData.ProcAnimType.FLY:
			target_pos_y = 1.0 + sin(proc_time * 3.0) * 0.2
			target_rot_x = 0.3
		PetData.ProcAnimType.ROLL:
			target_rot_z += delta * 15.0
		PetData.ProcAnimType.SHAKE:
			mesh_root.position.x = sin(proc_time * 25.0) * 0.1
			target_rot_z = sin(proc_time * 20.0) * 0.1
		PetData.ProcAnimType.FLIP:
			var action_start_time = current_action_state.get("start_time", 0.0)
			if action_start_time > 0.0:
				var flip_elapsed = Time.get_unix_time_from_system() - action_start_time
				var flip_duration = current_action_state.get("duration", 2000) / 1000.0
				var t = clamp(flip_elapsed / flip_duration, 0.0, 1.0)
				var flip_speed = TAU / flip_duration
				proc_rot_x = flip_elapsed * flip_speed
				target_rot_x = proc_rot_x
				var jump_height = 0.6 * (4.0 * t * (1.0 - t))
				target_pos_y = jump_height
				if t > 0.15 and t < 0.85:
					target_rot_z = sin(flip_elapsed * 10.0) * 0.08
				else:
					target_rot_z = 0.0
			else:
				proc_rot_x = 0.0
				target_pos_y = 0.0
				target_rot_x = 0.0
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

## 更新状态值（供主控制器调用）
func update_state_vars(anim_state: int, proc_type: int, proc_t: float, tilt: float, rot_y: float, rot_x: float, shake: float, action_state: Dictionary) -> void:
	current_anim_state = anim_state
	proc_anim_type = proc_type
	proc_time = proc_t
	tilt_angle = tilt
	proc_rot_y = rot_y
	proc_rot_x = rot_x
	shake_intensity = shake
	current_action_state = action_state

## 获取状态值（供主控制器读取）
func get_state_vars() -> Dictionary:
	return {
		"proc_rot_y": proc_rot_y,
		"proc_rot_x": proc_rot_x,
		"proc_anim_type": proc_anim_type
	}
