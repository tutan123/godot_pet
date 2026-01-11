extends CharacterBody3D

## PetController.gd
## 主控制器：协调各个功能模块，实现完整的宠物控制逻辑

## 导入模块脚本
const PetData = preload("res://scripts/pet_data.gd")
const PetInputScript = preload("res://scripts/pet_input.gd")
const PetPhysicsScript = preload("res://scripts/pet_physics.gd")
const PetAnimationScript = preload("res://scripts/pet_animation.gd")
const PetInteractionScript = preload("res://scripts/pet_interaction.gd")
const PetMessagingScript = preload("res://scripts/pet_messaging.gd")

## 节点引用
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var ws_client = get_node_or_null("/root/Main/WebSocketClient")
@onready var mesh_root = $Player

## 功能模块引用（可选，如果场景中没有则会在 _ready 中创建）
var input_module
var physics_module
var animation_module
var interaction_module
var messaging_module

@export_group("Movement Settings")
@export var walk_speed: float = 3.0
@export var run_speed: float = 7.0
@export var rotation_speed: float = 12.0
@export var jump_velocity: float = 6.5
@export var push_force: float = 0.5

@export_group("Interaction Settings")
@export var drag_height: float = 1.5

# 内部状态变量
var target_position: Vector3
var is_server_moving: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_anim_state: int = PetData.AnimState.IDLE
var proc_anim_type: int = PetData.ProcAnimType.NONE

# 程序化动作变量
var proc_time: float = 0.0
var shake_intensity: float = 0.0
var tilt_angle: float = 0.0
var proc_rot_y: float = 0.0
var proc_rot_x: float = 0.0

# 状态声明式动作管理
var current_action_state: Dictionary = {}
var action_queue: Array[Dictionary] = []
var action_lock_time: float = 0.0

# 用于定时上报位置
var last_jump_pressed: bool = false

# 用于服务端高频同步的插值缓冲
var server_target_pos: Vector3
var use_high_freq_sync: bool = false

func _ready() -> void:
	target_position = global_position
	server_target_pos = global_position
	
	# 尝试从场景中获取模块（如果场景中有子节点）
	input_module = get_node_or_null("InputModule")
	physics_module = get_node_or_null("PhysicsModule")
	animation_module = get_node_or_null("AnimationModule")
	interaction_module = get_node_or_null("InteractionModule")
	messaging_module = get_node_or_null("MessagingModule")
	
	# 初始化模块（如果场景中没有，则创建新实例）
	if not input_module:
		input_module = PetInputScript.new()
		add_child(input_module)
		input_module.name = "InputModule"
	
	if not physics_module:
		physics_module = PetPhysicsScript.new()
		add_child(physics_module)
		physics_module.name = "PhysicsModule"
	
	if not animation_module:
		animation_module = PetAnimationScript.new()
		add_child(animation_module)
		animation_module.name = "AnimationModule"
	
	if not interaction_module:
		interaction_module = PetInteractionScript.new()
		add_child(interaction_module)
		interaction_module.name = "InteractionModule"
	
	if not messaging_module:
		messaging_module = PetMessagingScript.new()
		add_child(messaging_module)
		messaging_module.name = "MessagingModule"
	
	# 配置物理模块
	physics_module.walk_speed = walk_speed
	physics_module.run_speed = run_speed
	physics_module.rotation_speed = rotation_speed
	physics_module.jump_velocity = jump_velocity
	physics_module.push_force = push_force
	physics_module.gravity = gravity
	
	# 配置交互模块
	interaction_module.drag_height = drag_height
	
	# 配置消息模块
	messaging_module.ws_client = ws_client
	messaging_module.sync_interval = 1.0
	
	# 配置动画模块
	animation_module.animation_tree = animation_tree
	animation_module.mesh_root = mesh_root
	
	# 连接信号
	if ws_client:
		ws_client.message_received.connect(_on_ws_message)
	
	physics_module.jump_triggered.connect(_on_jump_triggered)
	physics_module.collision_detected.connect(_on_collision_detected)
	interaction_module.interaction_sent.connect(_on_interaction_sent)
	interaction_module.clicked.connect(_on_clicked)
	animation_module.anim_state_changed.connect(_on_anim_state_changed)
	messaging_module.action_state_applied.connect(_on_action_state_applied)
	messaging_module.move_to_received.connect(_on_move_to_received)
	messaging_module.position_set_received.connect(_on_position_set_received)
	
	# 验证 AnimationTree 和动画资源
	if animation_tree:
		animation_tree.active = true
		_validate_animation_tree()
	
	input_ray_pickable = true

func _validate_animation_tree() -> void:
	if not animation_tree:
		return
	
	var anim_player_path = animation_tree.anim_player
	if anim_player_path:
		var player_node = animation_tree.get_node_or_null(anim_player_path)
		if player_node and player_node is AnimationPlayer:
			var anim_list = player_node.get_animation_list()
			_log("[Pet] Available animations: %s" % str(anim_list))
			for anim_name in ["idle", "walk", "run", "jump", "wave"]:
				if anim_name in anim_list:
					_log("[Pet] ✓ Animation '%s' found" % anim_name)
				else:
					_log("[Pet] ✗ Animation '%s' NOT found!" % anim_name)
		else:
			_log("[Pet] ERROR: AnimationPlayer not found at path: %s" % str(anim_player_path))
	
	var test_param = "parameters/locomotion/blend_position"
	var test_value = animation_tree.get(test_param)
	if test_value != null:
		_log("[Pet] ✓ Parameter '%s' exists = %s" % [test_param, test_value])
	else:
		_log("[Pet] ✗ Parameter '%s' does not exist or is null" % test_param)
		_log("[Pet] WARNING: BlendTree parameter might not be configured correctly!")
	
	var tree_root = animation_tree.tree_root
	if tree_root:
		_log("[Pet] Tree root type: %s" % tree_root.get_class())
	else:
		_log("[Pet] ERROR: Tree root is null!")

func _input_event(_camera: Camera3D, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if interaction_module:
		interaction_module.handle_input_event(event, self, mesh_root, proc_time, proc_anim_type)

func _physics_process(delta: float) -> void:
	proc_time += delta
	
	# 更新模块状态变量
	_update_module_state_vars()
	
	# 1. 前置检查和更新
	messaging_module.update_action_state_expiry()
	messaging_module.update_state_sync(delta, self, current_anim_state, interaction_module.is_dragging, _anim_state_to_string)
	
	# 2. 拖拽处理（最高优先级）
	if interaction_module.is_dragging:
		interaction_module.handle_dragging(delta, self, mesh_root, proc_time)
		animation_module.set_anim_state(PetData.AnimState.JUMP)
		return
	
	# 3. 输入和状态检测
	var input_data = input_module.get_input_data()
	
	# 更新物理模块状态
	physics_module.target_position = target_position
	physics_module.is_server_moving = is_server_moving
	physics_module.use_high_freq_sync = use_high_freq_sync
	physics_module.server_target_pos = server_target_pos
	
	var movement_data = physics_module.calculate_movement(input_data, global_position, delta)
	
	# 处理高频同步
	if use_high_freq_sync:
		global_position = global_position.lerp(server_target_pos, 0.2)
	
	# 4. 应用物理和移动
	physics_module.apply_physics(movement_data, self, delta)
	tilt_angle = physics_module.apply_movement(movement_data, self, delta)
	
	# 处理跳跃
	var jump_triggered = physics_module.handle_jump(input_data, self)
	if jump_triggered:
		animation_module.set_anim_state(PetData.AnimState.JUMP)
		current_anim_state = PetData.AnimState.JUMP
	last_jump_pressed = input_data.jump_pressed
	
	move_and_slide()
	
	# 5. 落地后状态修正（必须在 move_and_slide 之后）
	_handle_landing_state_fix(input_data, movement_data)
	
	# 6. 碰撞和物理交互
	physics_module.handle_collisions(self)
	physics_module.handle_physics_push(self)
	
	# 7. 动画状态切换（根据移动数据）
	var is_locomotion_action = false
	if not current_action_state.is_empty():
		var action_name = current_action_state.get("name", "")
		if action_name == "walk" or action_name == "run" or action_name == "idle":
			is_locomotion_action = true
			
	if is_on_floor() and (current_action_state.is_empty() or is_locomotion_action):
		if movement_data.target_anim_state != current_anim_state:
			_log("[Pet-Logic] Local physics changed state: %s -> %s" % [_anim_state_to_string(current_anim_state), _anim_state_to_string(movement_data.target_anim_state)])
			animation_module.set_anim_state(movement_data.target_anim_state)
			current_anim_state = movement_data.target_anim_state

func _process(delta: float) -> void:
	# 应用程序化动画 (叠加效果)
	if animation_module:
		animation_module.apply_procedural_fx(delta, interaction_module.is_dragging)

func _handle_landing_state_fix(input_data, movement_data) -> void:
	# 核心修复：只有当角色在向下落（y速度 < 0）且踩到地时，才认为是真正落地
	if not is_on_floor() or velocity.y > 0:
		return
	
	var is_jump_state = current_anim_state == PetData.AnimState.JUMP
	
	if is_jump_state:
		# 落地后清除跳跃状态
		if animation_tree:
			animation_tree.set("parameters/jump_blend/blend_amount", 0.0)
		
		var target_state: int
		if input_data.direction.length() > 0.1:
			target_state = PetData.AnimState.RUN if input_data.is_running else PetData.AnimState.WALK
		else:
			target_state = PetData.AnimState.IDLE
		
		animation_module.force_anim_state(target_state)
		current_anim_state = target_state
		_log("[Pet] Forced animation switch after landing: jump -> %s" % _anim_state_to_string(target_state))
	elif current_action_state.is_empty() and input_data.direction.length() < 0.1:
		if current_anim_state != PetData.AnimState.IDLE:
			animation_module.set_anim_state(PetData.AnimState.IDLE)
			current_anim_state = PetData.AnimState.IDLE

func _update_module_state_vars() -> void:
	# 更新动画模块的状态变量
	if animation_module:
		animation_module.update_state_vars(
			current_anim_state,
			proc_anim_type,
			proc_time,
			tilt_angle,
			proc_rot_y,
			proc_rot_x,
			shake_intensity,
			current_action_state
		)
	
	# 从动画模块读取更新的值（程序化动画可能会修改这些值）
	if animation_module:
		var state_vars = animation_module.get_state_vars()
		proc_rot_y = state_vars.get("proc_rot_y", proc_rot_y)
		proc_rot_x = state_vars.get("proc_rot_x", proc_rot_x)
		proc_anim_type = state_vars.get("proc_anim_type", proc_anim_type)

func _on_ws_message(type: String, data: Dictionary) -> void:
	if messaging_module:
		messaging_module.handle_ws_message(type, data, animation_tree)

func _on_jump_triggered(velocity_y: float) -> void:
	if messaging_module and messaging_module.ws_client and messaging_module.ws_client.is_connected:
		messaging_module.send_interaction("jump", Vector3.ZERO, global_position)

func _on_collision_detected(collision_data: Dictionary) -> void:
	if messaging_module:
		messaging_module.send_interaction("collision", collision_data, global_position)

func _on_interaction_sent(_action: String, _data: Dictionary) -> void:
	# 交互消息已由 interaction_module 发送，这里可以添加额外处理
	pass

func _on_clicked() -> void:
	# 点击事件已由 interaction_module 处理，这里可以添加额外处理
	pass

func _on_anim_state_changed(old_state: int, new_state: int) -> void:
	current_anim_state = new_state
	_log("[Pet] Animation state: %s -> %s" % [_anim_state_to_string(old_state), _anim_state_to_string(new_state)])

func _on_action_state_applied(action_state: Dictionary) -> void:
	current_action_state = action_state
	action_lock_time = messaging_module.action_lock_time
	
	# 切换动画
	var action_name = action_state.get("name", "idle")
	animation_module.switch_anim(action_name)
	
	# 如果是程序化动画，更新类型
	if animation_module.is_procedural_anim(action_name):
		proc_anim_type = animation_module.proc_anim_type
	
	_log("[Pet] Applied action state: %s (priority: %d, duration: %dms, interruptible: %s)" % [
		action_name,
		action_state.get("priority", 0),
		action_state.get("duration", 0),
		action_state.get("interruptible", true)
	])

func _on_move_to_received(target: Vector3) -> void:
	target_position = target
	is_server_moving = true

func _on_position_set_received(pos: Vector3) -> void:
	server_target_pos = pos
	use_high_freq_sync = true
	is_server_moving = false

## 工具函数
func _log(msg: String) -> void:
	var time_dict = Time.get_time_dict_from_system()
	var unix_time = Time.get_unix_time_from_system()
	var msec = int((unix_time - floor(unix_time)) * 1000)
	print("[%02d:%02d:%02d.%03d] %s" % [time_dict.hour, time_dict.minute, time_dict.second, msec, msg])

func _anim_state_to_string(state: int) -> String:
	if animation_module:
		return animation_module.anim_state_to_string(state)
	match state:
		PetData.AnimState.IDLE: return "idle"
		PetData.AnimState.WALK: return "walk"
		PetData.AnimState.RUN: return "run"
		PetData.AnimState.JUMP: return "jump"
		PetData.AnimState.WAVE: return "wave"
		_: return "idle"
