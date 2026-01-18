extends Node

## pet_animation.gd
## 动画管理模块：状态驱动与循环保护（修正语法版）

const PetData = preload("res://scripts/pet_data.gd")

signal anim_state_changed(old_state: int, new_state: int)
signal procedural_anim_finished(anim_name: String)

# --- 节点引用 ---
var animation_tree: AnimationTree
var mesh_root: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer

# --- 状态变量 ---
var current_anim_state: int = PetData.AnimState.IDLE
var proc_anim_type: int = PetData.ProcAnimType.NONE
var proc_time: float = 0.0
var tilt_angle: float = 0.0
var current_action_state: Dictionary = {}
var proc_rot_y: float = 0.0
var proc_rot_x: float = 0.0

## 设置动画状态
func set_anim_state(new_state: int, force: bool = false) -> void:
	if not force and current_anim_state == new_state:
		return
	
	if not animation_tree:
		return
	
	var prev_state = current_anim_state
	
	if not animation_tree.active:
		animation_tree.active = true
	
	# 同步混合树参数
	match new_state:
		PetData.AnimState.IDLE:
			animation_tree.set("parameters/jump_blend/blend_amount", 0.0)
		PetData.AnimState.WALK, PetData.AnimState.RUN:
			animation_tree.set("parameters/jump_blend/blend_amount", 0.0)
		PetData.AnimState.JUMP:
			animation_tree.set("parameters/jump_blend/blend_amount", 1.0)
	
	current_anim_state = new_state
	anim_state_changed.emit(prev_state, new_state)

## 切换动作入口
func switch_anim(anim_name: String) -> void:
	var normalized_name = normalize_action_name(anim_name)
	
	# 1. 检查程序化动画
	if is_procedural_anim(normalized_name):
		clear_procedural_anim_state()
		set_procedural_anim(normalized_name)
		proc_time = 0.0
		return
	
	# 2. 基础移动状态
	var base_animations = ["idle", "stand", "walk", "run", "jump"]
	if normalized_name in base_animations:
		# 映射：如果 idle 不存在，尝试 stand
		var target_anim = normalized_name
		if target_anim == "idle" and anim_player and not anim_player.has_animation("idle"):
			if anim_player.has_animation("stand"):
				target_anim = "stand"
		
		if anim_player and anim_player.is_playing():
			if not target_anim in anim_player.current_animation:
				anim_player.stop()
		
		clear_procedural_anim_state()
		set_anim_state(string_to_anim_state(target_anim))
		return
	
	# 3. 片段播放
	_play_animation_directly(normalized_name)

func _play_animation_directly(anim_name: String) -> void:
	if not anim_player or not anim_player.has_animation(anim_name):
		return
	
	clear_procedural_anim_state()
	if animation_tree:
		animation_tree.active = false
	
	anim_player.play(anim_name)
	_wait_for_anim_finish(anim_name)

func _wait_for_anim_finish(anim_name: String) -> void:
	await anim_player.animation_finished
	if anim_player.current_animation == anim_name:
		procedural_anim_finished.emit(anim_name)
		if animation_tree:
			animation_tree.active = true
		set_anim_state(PetData.AnimState.IDLE)

# --- 修正后的单行函数格式 ---

func normalize_action_name(n: String) -> String:
	return n.to_lower()

func is_procedural_anim(n: String) -> bool:
	return n in ["wave", "spin", "bounce", "fly", "roll", "shake", "flip", "dance"]

## 检查是否正在播放特殊（非循环/持续型）动画
func is_playing_special_anim() -> bool:
	# 程序化动作中，WAVE 和 FLIP 是有明确结束意义的
	if proc_anim_type in [PetData.ProcAnimType.WAVE, PetData.ProcAnimType.FLIP]:
		# 如果播放时间超过了预设时间（WAVE 2.5s, FLIP 2.0s），认为结束
		var duration = 2.5 if proc_anim_type == PetData.ProcAnimType.WAVE else 2.0
		return proc_time < duration
	
	# 如果正在播放 AnimationPlayer 里的非循环动画
	if anim_player and anim_player.is_playing():
		var anim = anim_player.get_animation(anim_player.current_animation)
		if anim and anim.loop_mode == Animation.LOOP_NONE:
			return true
			
	return false

func clear_procedural_anim_state() -> void:
	if proc_anim_type == PetData.ProcAnimType.WAVE or proc_anim_type == PetData.ProcAnimType.FLIP:
		# 恢复动画树控制
		if animation_tree: animation_tree.active = true

	if proc_anim_type == PetData.ProcAnimType.SPIN or proc_anim_type == PetData.ProcAnimType.DANCE:
		proc_rot_y = 0.0
	if proc_anim_type == PetData.ProcAnimType.FLIP:
		proc_rot_x = 0.0

	proc_anim_type = PetData.ProcAnimType.NONE

func set_procedural_anim(n: String) -> void:
	match n:
		"flip":
			proc_anim_type = PetData.ProcAnimType.FLIP
			proc_rot_x = 0.0
			proc_time = 0.0
			if animation_tree: animation_tree.active = false
		"wave":
			proc_anim_type = PetData.ProcAnimType.WAVE
			proc_time = 0.0
			if animation_tree: animation_tree.active = false
		"spin":
			proc_anim_type = PetData.ProcAnimType.SPIN
			proc_rot_y = 0.0
		"bounce":
			proc_anim_type = PetData.ProcAnimType.BOUNCE
		"fly":
			proc_anim_type = PetData.ProcAnimType.FLY
			proc_time = 0.0
		"roll":
			proc_anim_type = PetData.ProcAnimType.ROLL
		"shake":
			proc_anim_type = PetData.ProcAnimType.SHAKE
		"dance":
			proc_anim_type = PetData.ProcAnimType.DANCE
			proc_rot_y = 0.0

func string_to_anim_state(n: String) -> int:
	match n:
		"walk": return PetData.AnimState.WALK
		"run": return PetData.AnimState.RUN
		"jump": return PetData.AnimState.JUMP
		_: return PetData.AnimState.IDLE

func anim_state_to_string(state: int) -> String:
	match state:
		PetData.AnimState.WALK: return "walk"
		PetData.AnimState.RUN: return "run"
		PetData.AnimState.JUMP: return "jump"
		PetData.AnimState.WAVE: return "wave"
		_: return "idle"

func _apply_arm_wave_animation(_delta: float) -> void:
	# 简化版本：新版本可能不支持骨骼动画，直接返回
	pass

func apply_procedural_fx(delta: float, is_dragging: bool) -> void:
	if not mesh_root:
		return

	proc_time += delta

	# 初始化目标值
	var target_pos_y: float = 0.0
	var target_rot_z: float = 0.0
	var target_scale_y: float = 0.0

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
			# 飞行时的悬浮效果：相对于当前位置轻微上下浮动
			var base_height = 0.0  # 飞行时的基线高度
			var hover_offset = sin(proc_time * 2.0) * 0.1  # 轻微的上下浮动
			target_pos_y = base_height + hover_offset
		PetData.ProcAnimType.ROLL:
			target_rot_z += delta * 15.0
		PetData.ProcAnimType.SHAKE:
			mesh_root.position.x = sin(proc_time * 25.0) * 0.1
			target_rot_z = sin(proc_time * 20.0) * 0.1
		PetData.ProcAnimType.FLIP:
			var flip_duration = 2.0
			var t = clamp(proc_time / flip_duration, 0.0, 1.0)
			var flip_speed = TAU / flip_duration
			proc_rot_x = proc_time * flip_speed
			target_pos_y = 0.6 * (4.0 * t * (1.0 - t))
			if t > 0.15 and t < 0.85:
				target_rot_z = sin(proc_time * 10.0) * 0.08
		PetData.ProcAnimType.DANCE:
			target_rot_z = sin(proc_time * 8.0) * 0.2
			target_pos_y = abs(sin(proc_time * 6.0)) * 0.3
			proc_rot_y += delta * 30.0
			target_scale_y = 0.3 * (1.0 + sin(proc_time * 4.0) * 0.1)

	# C. 拖拽时的特殊覆盖
	if is_dragging:
		target_rot_z = sin(proc_time * 10.0) * 0.2

	# D. 最终平滑应用到模型
	if proc_anim_type != PetData.ProcAnimType.SHAKE:  # SHAKE单独处理X轴
		mesh_root.position.y = lerp(mesh_root.position.y, target_pos_y, 10.0 * delta)

	# X轴旋转（FLIP）
	if proc_anim_type == PetData.ProcAnimType.FLIP:
		mesh_root.rotation.x = proc_rot_x

	# Z轴旋转（各种动画）
	mesh_root.rotation.z = lerp(mesh_root.rotation.z, target_rot_z, 15.0 * delta)

	# Y轴旋转（SPIN, DANCE）
	if proc_anim_type == PetData.ProcAnimType.SPIN or proc_anim_type == PetData.ProcAnimType.DANCE:
		mesh_root.rotation.y = proc_rot_y

	# 缩放（WAVE, BOUNCE, DANCE）
	if target_scale_y > 0:
		mesh_root.scale.y = lerp(mesh_root.scale.y, target_scale_y, 10.0 * delta)
