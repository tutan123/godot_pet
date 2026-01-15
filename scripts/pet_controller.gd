extends CharacterBody3D

## PetController.gd
## 主控制器：协调各个功能模块，实现完整的宠物控制逻辑

const PetData = preload("res://scripts/pet_data.gd")
const PetInputScript = preload("res://scripts/pet_input.gd")
const PetPhysicsScript = preload("res://scripts/pet_physics.gd")
const PetAnimationScript = preload("res://scripts/pet_animation.gd")
const PetInteractionScript = preload("res://scripts/pet_interaction.gd")
const PetMessagingScript = preload("res://scripts/pet_messaging.gd")

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var ws_client = get_node_or_null("/root/Main/WebSocketClient")
@onready var mesh_root = $Player

var input_module
var physics_module
var animation_module
var interaction_module
var messaging_module

@export var walk_speed: float = 3.0
@export var run_speed: float = 7.0
@export var rotation_speed: float = 12.0
@export var jump_velocity: float = 6.5
@export var push_force: float = 0.5
@export var drag_height: float = 1.5
@export var click_move_speed: float = 3.0  # 点击移动的速度
@export var arrival_distance: float = 0.3  # 到达目标的距离阈值

var target_position: Vector3
var click_target_position: Vector3 = Vector3.ZERO  # 点击移动的目标位置
var is_moving_to_click: bool = false  # 是否正在移动到点击位置
var is_server_moving: bool = false
var is_flying: bool = false
var is_executing_scene: bool = false
var last_floor_collider: String = ""
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_anim_state: int = PetData.AnimState.IDLE
var current_action_state: Dictionary = {}
var use_high_freq_sync: bool = false
var server_target_pos: Vector3

func _ready() -> void:
	target_position = global_position
	server_target_pos = global_position
	
	input_module = PetInputScript.new(); add_child(input_module)
	physics_module = PetPhysicsScript.new(); add_child(physics_module)
	animation_module = PetAnimationScript.new(); add_child(animation_module)
	interaction_module = PetInteractionScript.new(); add_child(interaction_module)
	messaging_module = PetMessagingScript.new(); add_child(messaging_module)
	
	physics_module.walk_speed = walk_speed
	physics_module.run_speed = run_speed
	physics_module.rotation_speed = rotation_speed
	physics_module.jump_velocity = jump_velocity
	physics_module.push_force = push_force
	physics_module.gravity = gravity
	interaction_module.drag_height = drag_height
	messaging_module.ws_client = ws_client
	animation_module.animation_tree = animation_tree
	animation_module.mesh_root = mesh_root
	
	var skeleton_node = mesh_root.get_node_or_null("Skeleton/Skeleton3D")
	if skeleton_node: animation_module.setup_skeleton(skeleton_node)
	
	# 设置 stand、walk、run、jump 动画为循环模式
	var anim_player = mesh_root.get_node_or_null("AnimationPlayer")
	if anim_player:
		var stand_anim = anim_player.get_animation("stand")
		if stand_anim:
			stand_anim.loop_mode = Animation.LOOP_LINEAR
		var walk_anim = anim_player.get_animation("walk")
		if walk_anim:
			walk_anim.loop_mode = Animation.LOOP_LINEAR
		var run_anim = anim_player.get_animation("run")
		if run_anim:
			run_anim.loop_mode = Animation.LOOP_LINEAR
		var jump_anim = anim_player.get_animation("jump")
		if jump_anim:
			jump_anim.loop_mode = Animation.LOOP_LINEAR
	
	if ws_client: ws_client.message_received.connect(_on_ws_message)
	physics_module.jump_triggered.connect(_on_jump_triggered)
	physics_module.collision_detected.connect(_on_collision_detected)
	animation_module.anim_state_changed.connect(_on_anim_state_changed)
	animation_module.procedural_anim_finished.connect(_on_procedural_finished)
	
	# 关键修复：连接交互模块信号
	interaction_module.interaction_sent.connect(func(action, data): 
		messaging_module.send_interaction(action, data, global_position)
	)
	interaction_module.drag_started.connect(func(): _log("[Action] Drag Started"))
	interaction_module.drag_finished.connect(func(): _log("[Action] Drag Finished"))
	interaction_module.clicked.connect(func(): _log("[Action] Clicked"))
	interaction_module.ground_clicked.connect(_on_ground_clicked)
	
	messaging_module.action_state_applied.connect(_on_action_state_applied)
	messaging_module.move_to_received.connect(_on_move_to_received)
	messaging_module.position_set_received.connect(_on_position_set_received)
	messaging_module.scene_received.connect(_on_scene_received)
	messaging_module.dynamic_scene_received.connect(_on_dynamic_scene_received)
	
	if animation_tree: animation_tree.active = true
	
	# 启用鼠标交互（拖拽功能需要）
	input_ray_pickable = true
	
	_log("[System] Robot Initialized and Ready.")

func _physics_process(delta: float) -> void:
	# 动画模块现在内部管理计时器
	animation_module.update_state_vars(current_anim_state, current_action_state)
	
	# 马尔可夫性：持续检查动作状态是否过期
	messaging_module.update_action_state_expiry()
	
	messaging_module.update_state_sync(delta, self, current_anim_state, interaction_module.is_dragging, is_executing_scene, _anim_state_to_string)
	
	if interaction_module.is_dragging:
		is_executing_scene = false
		interaction_module.handle_dragging(delta, self, mesh_root, animation_module.proc_time)
		return

	if is_executing_scene: return
	
	# 马尔可夫性修复：基于当前状态决定是否允许本地 locomotion
	# 如果当前有服务器动作状态且不是基础移动，说明正在执行重要指令，让路
	var is_doing_important_action = not messaging_module.current_action_state.is_empty() and not messaging_module.current_action_state.get("is_locomotion", false)
	
	var input_data = input_module.get_input_data()
	
	# 如果用户按了键盘移动，取消点击移动
	if is_moving_to_click and input_data.direction.length() > 0.1:
		is_moving_to_click = false
		_log("[Move] Click movement cancelled by keyboard input")
	
	# 处理点击移动
	if is_moving_to_click:
		handle_click_movement(delta)
		return
	physics_module.target_position = target_position
	physics_module.is_server_moving = is_server_moving
	physics_module.is_flying = is_flying
	var movement_data = physics_module.calculate_movement(input_data, global_position, delta)
	
	# 检查是否在执行程序化动画（如 FLY）
	var is_procedural_active = animation_module.proc_anim_type != PetData.ProcAnimType.NONE
	
	# 如果是程序化动画（如 FLY），暂停物理引擎的 Y 轴重力，让程序化动画控制位置
	if not is_procedural_active:
		physics_module.apply_physics(movement_data, self, delta)
		physics_module.apply_movement(movement_data, self, delta)
		
		# 只有在没有重要服务器动作时才允许本地跳跃
		if not is_doing_important_action and physics_module.handle_jump(input_data, self):
			animation_module.set_anim_state(PetData.AnimState.JUMP)
	
	move_and_slide()
	
	# 程序化动画期间，物理引擎的 move_and_slide 可能覆盖了 mesh_root.position.y
	# 我们需要在 _process 中确保程序化动画的位置正确应用
	
	# 地面检测 Log
	if is_on_floor() and get_slide_collision_count() > 0:
		var coll = get_last_slide_collision()
		if coll and coll.get_collider():
			var floor_name = coll.get_collider().name
			if floor_name != last_floor_collider:
				_log("[Physics] Stepped onto: %s" % floor_name)
				last_floor_collider = floor_name

	physics_module.handle_collisions(self)
	# 关键修复：应用物理推力（让机器人能推动 RigidBody3D 物体，如球）
	physics_module.handle_physics_push(self)
	
	# 马尔可夫性：只有在没有重要服务器动作且在地面时，才允许本地 locomotion 状态切换
	if not is_doing_important_action and is_on_floor() and movement_data.target_anim_state != current_anim_state:
		_log("[Anim] State Change: %s -> %s" % [_anim_state_to_string(current_anim_state), _anim_state_to_string(movement_data.target_anim_state)])
		animation_module.set_anim_state(movement_data.target_anim_state)
		current_anim_state = movement_data.target_anim_state

func _process(delta: float) -> void:
	animation_module.apply_procedural_fx(delta, interaction_module.is_dragging)

func _input_event(_camera: Camera3D, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	# 将输入事件传递给交互模块处理
	if interaction_module:
		interaction_module.handle_input_event(event, self, mesh_root, animation_module.proc_time, animation_module.proc_anim_type)

func _input(event: InputEvent) -> void:
	# 只有在拖拽状态下，我们才需要全局捕获鼠标抬起事件，以确保拖拽正常结束
	if interaction_module and interaction_module.is_dragging:
		if event is InputEventMouseButton and not event.pressed:
			interaction_module.handle_input_event(event, self, mesh_root, animation_module.proc_time, animation_module.proc_anim_type)

func _unhandled_input(event: InputEvent) -> void:
	# 优雅方案：利用 Godot 的 _unhandled_input 机制处理地面点击
	# 只有当点击事件没有被 UI 拦截时（比如点在空地），此函数才会被触发
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if interaction_module:
			var ground_pos = interaction_module.get_ground_position_under_mouse()
			if ground_pos != Vector3.ZERO:
				interaction_module.ground_clicked.emit(ground_pos)
				interaction_module.show_target_indicator(ground_pos)

func _on_ws_message(type: String, data: Dictionary) -> void:
	messaging_module.handle_ws_message(type, data, animation_tree)

func _on_jump_triggered(_v): 
	_log("[Action] Jump Triggered")
	messaging_module.send_interaction("jump", {}, global_position)

func _on_collision_detected(data): 
	_log("[Collision] Hit: %s" % data.collider_name)
	messaging_module.send_interaction("collision", data, global_position)

func _on_anim_state_changed(_o, n): current_anim_state = n

func _on_procedural_finished(_name):
	# 当动画模块说播完了，我们才真正清除服务器动作状态（马尔可夫状态转移点）
	messaging_module.current_action_state = {}
	_log("[Action] Procedural Finished: %s" % _name)

func _on_action_state_applied(state):
	if is_executing_scene: return
	if not state is Dictionary or state.is_empty() or not state.has("name"):
		return
	_log("[Server] Executing Action: %s" % state.name)
	
	# 马尔可夫性：立即应用动作，基于当前状态决定表现
	# 不依赖时间锁定，让动画模块根据动作类型自行处理
	animation_module.switch_anim(state.name)
	
	# 特殊动作的物理状态设置（基于当前动作类型，而非时间）
	var action_name = state.name.to_lower()
	if action_name == "fly":
		is_flying = true
		# 给一个初始向上的速度，让物理引擎配合程序化动画
		velocity.y = 8.0
		# 确保程序化动画能持续足够长时间
		# 注意：proc_time 已经在 switch_anim 中重置为 0.0

func _on_move_to_received(target): target_position = target; is_server_moving = true

func _on_position_set_received(pos: Vector3) -> void:
	server_target_pos = pos
	use_high_freq_sync = true
	is_server_moving = false

func _on_scene_received(scene_name, _d): if scene_name == "welcome": _execute_welcome_scene()

func _on_dynamic_scene_received(steps): _execute_dynamic_scene(steps)

## 处理地面点击事件
func _on_ground_clicked(target_pos: Vector3) -> void:
	click_target_position = target_pos
	is_moving_to_click = true
	_log("[Move] Clicked to move to: %s" % target_pos)

## 处理点击移动逻辑
func handle_click_movement(delta: float) -> void:
	var to_target = click_target_position - global_position
	to_target.y = 0  # 忽略Y轴差异，只在地面移动
	
	var distance = to_target.length()
	
	# 检查是否到达目标
	if distance < arrival_distance:
		# 到达目标，停止移动
		is_moving_to_click = false
		velocity.x = 0
		velocity.z = 0
		_log("[Move] Arrived at target position")
		return
	
	# 计算移动方向
	var direction = to_target.normalized()
	
	# 应用移动速度
	velocity.x = direction.x * click_move_speed
	velocity.z = direction.z * click_move_speed
	
	# 旋转朝向目标
	var target_rotation = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, 10.0 * delta)
	
	# 设置动画状态（根据速度决定walk或run）
	var current_speed = Vector2(velocity.x, velocity.z).length()
	if current_speed > 0.1:
		var target_anim = PetData.AnimState.WALK
		if current_speed > walk_speed * 0.7:
			target_anim = PetData.AnimState.RUN
		
		if current_anim_state != target_anim:
			animation_module.set_anim_state(target_anim)
			current_anim_state = target_anim
	
	# 应用物理（重力等）
	physics_module.apply_physics(PetData.MovementData.new(), self, delta)
	move_and_slide()

func _execute_dynamic_scene(steps: Array) -> void:
	if is_executing_scene: return
	_log("[Scene] Dynamic Sequence Started (%d steps)" % steps.size())
	is_executing_scene = true
	var tween = create_tween().set_parallel(false)
	for step in steps:
		match step.type:
			"fly":
				var t = Vector3(step.target[0], step.target[1], step.target[2])
				tween.tween_callback(func(): is_flying = true; animation_module.set_anim_state(PetData.AnimState.JUMP))
				tween.tween_property(self, "global_position", t, step.duration).set_trans(Tween.TRANS_SINE)
			"land":
				var t = Vector3(step.target[0], step.target[1], step.target[2])
				tween.tween_property(self, "global_position", t, step.duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tween.tween_callback(func(): is_flying = false)
			"anim":
				tween.tween_callback(func(): _log("[Scene] Play Anim: %s" % step.name); animation_module.switch_anim(step.name))
				tween.tween_interval(step.duration)
	tween.tween_callback(func(): is_executing_scene = false; animation_module.switch_anim("idle"); _log("[Scene] Sequence Finished."))

func _execute_welcome_scene() -> void:
	_execute_dynamic_scene([
		{"type": "fly", "target": [0, 1.8, -4], "duration": 1.2},
		{"type": "land", "target": [0, 0.3, -4], "duration": 0.5},
		{"type": "anim", "name": "wave", "duration": 2.5},
		{"type": "anim", "name": "flip", "duration": 2.0}
	])

func _log(msg: String):
	var t = Time.get_time_dict_from_system()
	print("[%02d:%02d:%02d] %s" % [t.hour, t.minute, t.second, msg])

func _anim_state_to_string(s): return animation_module.anim_state_to_string(s) if animation_module else "idle"
