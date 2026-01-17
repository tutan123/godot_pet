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
		if anim_player and anim_player.is_playing():
			if not normalized_name in anim_player.current_animation:
				anim_player.stop()
		
		clear_procedural_anim_state()
		set_anim_state(string_to_anim_state(normalized_name))
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
	return n in ["fly", "wave", "flip", "spin"]

func clear_procedural_anim_state() -> void:
	proc_anim_type = PetData.ProcAnimType.NONE
	if animation_tree:
		animation_tree.active = true

func set_procedural_anim(n: String) -> void:
	match n:
		"fly":
			proc_anim_type = PetData.ProcAnimType.FLY
		"wave":
			proc_anim_type = PetData.ProcAnimType.WAVE
		"flip":
			proc_anim_type = PetData.ProcAnimType.FLIP
		"spin":
			proc_anim_type = PetData.ProcAnimType.SPIN

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

func apply_procedural_fx(delta: float, _is_dragging: bool) -> void:
	if not mesh_root:
		return
	proc_time += delta
	if proc_anim_type == PetData.ProcAnimType.FLY:
		# 飞行时的悬浮效果：相对于当前位置轻微上下浮动
		var base_height = 0.0  # 飞行时的基线高度
		var hover_offset = sin(proc_time * 2.0) * 0.1  # 轻微的上下浮动
		mesh_root.position.y = lerp(mesh_root.position.y, base_height + hover_offset, 3.0 * delta)
	else:
		# 非飞行状态：平滑回到地面高度
		mesh_root.position.y = lerp(mesh_root.position.y, 0.0, 5.0 * delta)
