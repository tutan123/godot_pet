extends Node

## pet_messaging.gd
## 消息处理模块：负责 WebSocket 消息的发送和接收处理

const PetData = preload("res://scripts/pet_data.gd")

## 信号定义
signal action_state_applied(action_state: Dictionary)
signal status_updated(status_data: Dictionary)
signal move_to_received(target: Vector3)
signal position_set_received(pos: Vector3)
signal scene_received(scene_name: String, data: Dictionary)
signal dynamic_scene_received(steps: Array)
signal eqs_query_received(data: Dictionary)

## 节点引用（通过主控制器传递）
var ws_client: Node

## 状态变量（通过主控制器传递）
var current_action_state: Dictionary = {}
var action_lock_time: float = 0.0
var sync_timer: float = 0.0
var sync_interval: float = 0.05 # 提升到 20Hz (50ms)

## 处理 WebSocket 消息
func handle_ws_message(type: String, data: Dictionary, animation_tree: AnimationTree) -> void:
	match type:
		"bt_output":
			if data.has("actionState"):
				var action_state = data["actionState"]
				apply_action_state(action_state, animation_tree)
			elif data.has("actions"): # 支持动作序列数组
				var actions = data["actions"]
				if actions is Array:
					for act in actions:
						_handle_single_action_data(act, animation_tree)
			elif data.has("action"):
				_handle_single_action_data(data["action"], animation_tree)
		"status_update":
			status_updated.emit(data)
		"move_to":
			if data.has("target"):
				var t = data["target"]
				move_to_received.emit(Vector3(t[0], t[1], t[2]))
		"set_position":
			if data.has("pos"):
				var p = data["pos"]
				position_set_received.emit(Vector3(p[0], p[1], p[2]))
		"scene_trigger":
			if data.has("scene"):
				scene_received.emit(data["scene"], data.get("data", {}))
		"dynamic_scene":
			if data.has("steps"):
				dynamic_scene_received.emit(data["steps"])
		"eqs_query":
			# EQS 查询请求，转发给 EQS 适配器处理
			eqs_query_received.emit(data)

func _handle_single_action_data(action_data: Variant, animation_tree: AnimationTree) -> void:
	var action_name = ""
	if action_data is String:
		action_name = action_data.to_lower()
	elif action_data is Dictionary:
		action_name = action_data.get("name", "idle").to_lower()

	# 调试：记录接收到的动作
	print("[Action] Received action: %s (original: %s)" % [action_name, str(action_data)])

	# 特殊处理：FLY 动作应该触发程序化动画，而不是基础动画
	if action_name == "fly":
		action_state_applied.emit({
			"name": "fly",
			"priority": 80,  # 更高的优先级
			"duration": 2000,  # 2秒飞行时间
			"interruptible": true
		})
		return

	apply_action_state({
		"name": action_name,
		"priority": 50,
		"interruptible": true
	}, animation_tree)

## 应用动作状态（马尔可夫性优化：事件驱动）
func apply_action_state(action_state: Dictionary, animation_tree: AnimationTree) -> void:
	var action_name = action_state.get("name", "idle").to_lower()
	var priority = action_state.get("priority", 50)
	var interruptible = action_state.get("interruptible", true)

	# 🎯 马尔可夫性核心：优先级判断只基于当前状态，不依赖历史时间
	var current_priority = current_action_state.get("priority", 0)
	var current_interruptible = current_action_state.get("interruptible", true)

	# 判断是否应该中断当前动作（纯状态驱动）
	var should_interrupt = false
	if current_action_state.is_empty():
		should_interrupt = true  # 无当前动作，直接执行
	elif priority > current_priority:
		should_interrupt = true  # 更高优先级，中断当前
	elif interruptible and current_interruptible and priority >= current_priority:
		should_interrupt = true  # 同等优先级但都可中断

	if should_interrupt:
		# 更新当前动作状态（去掉所有时间相关字段）
		current_action_state = {
			"name": action_name,
			"priority": priority,
			"interruptible": interruptible,
			"is_locomotion": action_name in ["walk", "run", "idle"]
		}

		# 处理基础移动动作
		if current_action_state.is_locomotion:
			action_lock_time = 0.0
			if animation_tree and action_state.has("speed"):
				var speed_normalized = action_state.get("speed", 0.5)
				animation_tree.set("parameters/locomotion/blend_position", speed_normalized)
		else:
			# 非基础移动动作：发出信号，等待动画完成信号清除状态
			action_lock_time = 0.0
			action_state_applied.emit(current_action_state)

## 更新动作状态过期检查
func update_action_state_expiry() -> void:
	# 废弃：现在由动画模块的信号驱动清除，避免双重计时冲突
	pass

## 发送交互消息
func send_interaction(action: String, extra_data: Variant, character_position: Vector3) -> void:
	if not ws_client or not ws_client.is_connected_to_server():
		return
	
	var data = {
		"action": action,
		"position": [character_position.x, character_position.y, character_position.z]
	}
	
	if extra_data is Dictionary:
		for key in extra_data.keys():
			data[key] = extra_data[key]
	
	ws_client.send_message("interaction", data)

## 发送状态同步
func send_state_sync(character_body: CharacterBody3D, current_anim_state: int, is_dragging: bool, is_executing_scene: bool, anim_state_to_string_func: Callable) -> void:
	if not ws_client or not ws_client.is_connected_to_server():
		return

	var focus_owner = get_viewport().gui_get_focus_owner()
	var is_typing = focus_owner is LineEdit
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var is_moving_locally = input_dir.length() > 0.1 and not is_typing
	var is_jump_pressed = Input.is_action_pressed("jump") and not is_typing

	# 获取舞台位置
	var stage_position = null
	var stage_node = character_body.get_node_or_null("/root/Main/NavigationRegion3D/StageDecor/Stage")
	if stage_node:
		stage_position = [stage_node.global_position.x, stage_node.global_position.y, stage_node.global_position.z]

	# 关键修复：检测真实碰撞（排除地板），防止连环跳
	var is_in_collision = false
	if character_body.get_slide_collision_count() > 0:
		for i in range(character_body.get_slide_collision_count()):
			var coll = character_body.get_slide_collision(i)
			# 如果碰撞法线 y 值很低，说明是撞到了墙或者台阶边缘
			if coll.get_normal().y < 0.5:
				is_in_collision = true
				break

	ws_client.send_message("state_sync", {
		"position": [character_body.global_position.x, character_body.global_position.y, character_body.global_position.z],
		"current_action": anim_state_to_string_func.call(current_anim_state),
		"is_dragging": is_dragging,
		"is_executing_scene": is_executing_scene, # 重要：同步给大脑
		"is_on_floor": character_body.is_on_floor(),
		"is_in_collision": is_in_collision, # 新增：准确同步碰撞状态
		"is_moving_locally": is_moving_locally,
		"is_jump_pressed": is_jump_pressed,
		"velocity": [character_body.velocity.x, character_body.velocity.y, character_body.velocity.z],
		"stage_position": stage_position,  # 新增：舞台位置
		# 战术状态同步 (符合马尔可夫性，让大脑感知物理状态机)
		"jump_push_pending": character_body.physics_module.jump_push_pending if "physics_module" in character_body else false,
		"jump_start_height": character_body.physics_module.jump_start_height if "physics_module" in character_body else 0.0,
		"is_playing_special_anim": character_body.animation_module.is_playing_special_anim() if "animation_module" in character_body else false
	})

## 更新状态同步定时器
func update_state_sync(delta: float, character_body: CharacterBody3D, current_anim_state: int, is_dragging: bool, is_executing_scene: bool, anim_state_to_string_func: Callable) -> void:
	sync_timer += delta
	if sync_timer >= sync_interval:
		send_state_sync(character_body, current_anim_state, is_dragging, is_executing_scene, anim_state_to_string_func)
		sync_timer = 0.0
