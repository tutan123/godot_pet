extends CharacterBody3D

## PetController.gd
## 主控制器：满血复原重构版
## 100% 还原原始动画循环与物理同步逻辑，同时保持模块化架构

const PetData = preload("res://scripts/pet_data.gd")
const PetInputScript = preload("res://scripts/pet_input.gd")
const PetPhysicsScript = preload("res://scripts/pet_physics.gd")
const PetAnimationScript = preload("res://scripts/pet_animation.gd")
const PetInteractionScript = preload("res://scripts/pet_interaction.gd")
const PetMessagingScript = preload("res://scripts/pet_messaging.gd")
const EQSAdapterScript = preload("res://scripts/eqs_adapter.gd")
const SceneObjectSyncScript = preload("res://scripts/scene_object_sync.gd")
const Logger = preload("res://scripts/logger.gd")

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var ws_client = get_node_or_null("/root/Main/WebSocketClient")
@onready var mesh_root = $Player

# --- 模块实例 ---
var input_module
var physics_module
var animation_module
var interaction_module
var messaging_module
var eqs_adapter: Node # 改为通用 Node 类型
var scene_object_sync: Node

# --- 核心可调参数 ---
@export var walk_speed: float = 3.0
@export var run_speed: float = 7.0
@export var rotation_speed: float = 12.0
@export var jump_velocity: float = 6.5
@export var push_force: float = 0.5
@export var drag_height: float = 1.5
@export var click_move_speed: float = 3.0
@export var arrival_distance: float = 0.3

# --- 核心状态 ---
var target_position: Vector3
var click_target_position: Vector3 = Vector3.ZERO
var server_target_pos: Vector3
var is_moving_to_click: bool = false
var is_server_moving: bool = false
var is_flying: bool = false
var is_executing_scene: bool = false
var last_floor_collider: String = ""
var current_anim_state: int = PetData.AnimState.IDLE
var current_action_state: Dictionary = {}
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var control_mode: int = PetData.ControlMode.USER  # 控制模式：解耦用户控制与AI战术

# --- 日志去重 ---
var log_history: Dictionary = {}
const LOG_COOLDOWN_MS = 3000

func _ready() -> void:
	target_position = global_position
	server_target_pos = global_position
	
	input_module = PetInputScript.new()
	add_child(input_module)
	physics_module = PetPhysicsScript.new()
	add_child(physics_module)
	animation_module = PetAnimationScript.new()
	add_child(animation_module)
	interaction_module = PetInteractionScript.new()
	add_child(interaction_module)
	messaging_module = PetMessagingScript.new()
	add_child(messaging_module)
	eqs_adapter = EQSAdapterScript.new()
	add_child(eqs_adapter)
	scene_object_sync = SceneObjectSyncScript.new()
	add_child(scene_object_sync)
	
	animation_module.animation_tree = animation_tree
	animation_module.mesh_root = mesh_root
	var anim_p = mesh_root.get_node_or_null("AnimationPlayer")
	if anim_p:
		animation_module.anim_player = anim_p

	# 🎯 P1：初始化BlendTree扩展（连续状态空间）
	animation_module._init_blend_tree_extensions()

	for anim_n in ["idle", "stand", "walk", "run", "jump"]:
			if anim_p.has_animation(anim_n):
				var anim = anim_p.get_animation(anim_n)
				if anim:
					anim.loop_mode = Animation.LOOP_LINEAR
			else:
				# 静默处理不存在的动画，避免控制台刷红
				pass
	
	messaging_module.ws_client = ws_client
	scene_object_sync.ws_client = ws_client
	eqs_adapter.ws_client = ws_client
	
	# 查找并初始化导航网格（EQS查询需要）
	var navmesh_node = get_node_or_null("/root/Main/NavigationRegion3D")
	if navmesh_node:
		eqs_adapter.navmesh = navmesh_node
		_log("[System] Navigation mesh connected to EQS adapter")

		# 验证导航网格状态（但不重新烘焙）
		_verify_navigation_mesh(navmesh_node)
	else:
		_log("[System] Warning: Navigation mesh not found, EQS will use fallback strategies")

## 验证导航网格状态
func _verify_navigation_mesh(navmesh_node: NavigationRegion3D) -> void:
	if not navmesh_node:
		return

	# 检查导航网格资源
	var navigation_mesh = navmesh_node.get_navigation_mesh()
	if not navigation_mesh:
		_log("[System] Warning: Navigation mesh resource is null")
		return

	# 检查烘焙状态
	# 使用属性访问替代函数调用，确保 Godot 4 兼容性
	var vertices = navigation_mesh.vertices
	var poly_count = navigation_mesh.get_polygon_count()

	_log("[System] Navigation mesh status:")
	_log("[System]   - Vertices: %d" % vertices.size())
	_log("[System]   - Polygons: %d" % poly_count)
	_log("[System]   - RID valid: %s" % (navmesh_node.get_rid() != RID()))

	if vertices.size() == 0 or poly_count == 0:
		_log("[System] Warning: Navigation mesh appears to be unbaked or empty")
		
		# 尝试在运行时自动烘焙
		_log("[System] Attempting automatic runtime baking (synchronous)...")
		if navmesh_node.has_method("bake_navigation_mesh"):
			navmesh_node.show()
			navmesh_node.bake_navigation_mesh(false)
			
			var new_vertices = navmesh_node.navigation_mesh.vertices
			var new_polys = navmesh_node.navigation_mesh.get_polygon_count()
			_log("[System] Runtime bake result: %d vertices, %d polygons" % [new_vertices.size(), new_polys])
	else:
		_log("[System] Navigation mesh is ready with %d vertices and %d polygons" % [vertices.size(), poly_count])
	
	_update_module_params()
	_connect_signals()
	
	if animation_tree:
		animation_tree.active = true
	input_ray_pickable = true

	# 连接WebSocket消息接收信号
	if ws_client:
		ws_client.message_received.connect(_on_ws_message)

	_log("[System] Robot Initialized and Ready.")

func _update_module_params() -> void:
	physics_module.walk_speed = walk_speed
	physics_module.run_speed = run_speed
	physics_module.rotation_speed = rotation_speed
	physics_module.jump_velocity = jump_velocity
	physics_module.push_force = push_force
	physics_module.gravity = gravity
	interaction_module.drag_height = drag_height

func _connect_signals() -> void:
	physics_module.jump_triggered.connect(_on_jump_triggered)
	physics_module.collision_detected.connect(_on_collision_detected)
	animation_module.anim_state_changed.connect(_on_anim_state_changed)
	animation_module.procedural_anim_finished.connect(_on_procedural_finished)
	eqs_adapter.eqs_result_ready.connect(_on_eqs_result_ready)
	messaging_module.action_state_applied.connect(_on_action_state_applied)
	messaging_module.status_updated.connect(_on_status_updated)
	messaging_module.move_to_received.connect(_on_move_to_received)
	messaging_module.position_set_received.connect(_on_position_set_received)
	messaging_module.scene_received.connect(_on_scene_received)
	messaging_module.dynamic_scene_received.connect(_on_dynamic_scene_received)
	messaging_module.eqs_query_received.connect(_on_eqs_query_received)
	interaction_module.interaction_sent.connect(_on_interaction_sent)
	interaction_module.ground_clicked.connect(_on_ground_clicked)

func _on_interaction_sent(action: String, data: Dictionary) -> void:
	messaging_module.send_interaction(action, data, global_position)

func _process(delta: float) -> void:
	animation_module.apply_procedural_fx(delta, interaction_module.is_dragging)

func _input_event(_camera: Camera3D, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	# 将输入事件传递给交互模块处理（点击宠物本身等）
	if interaction_module:
		interaction_module.handle_input_event(event, self, mesh_root, animation_module.proc_time, animation_module.proc_anim_type)

func _input(event: InputEvent) -> void:
	# 捕获全局鼠标移动和松开事件，用于处理拖拽启动和结束
	if interaction_module:
		# 只有在可能发生拖拽（已按下或正在拖拽）时才捕获全局事件
		if interaction_module.click_start_time > 0 or interaction_module.is_dragging:
			interaction_module.handle_input_event(event, self, mesh_root, animation_module.proc_time, animation_module.proc_anim_type)

func _unhandled_input(event: InputEvent) -> void:
	# 处理地面点击事件
	# 只有当点击事件没有被 UI 拦截时，此函数才会被触发
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if interaction_module:
			var ground_pos = interaction_module.get_ground_position_under_mouse()
			if ground_pos != Vector3.ZERO:
				interaction_module.ground_clicked.emit(ground_pos)
				interaction_module.show_target_indicator(ground_pos)

func _physics_process(delta: float) -> void:
	animation_module.current_anim_state = current_anim_state
	animation_module.current_action_state = current_action_state

	if interaction_module.is_dragging:
		is_executing_scene = false
		interaction_module.handle_dragging(delta, self, mesh_root, animation_module.proc_time)
		# 即使在拖拽中也要同步状态，确保前端 isDragging 更新
		_sync_animation_and_report(delta, false)
		return

	if is_executing_scene:
		return
		
	var is_doing_important_action = not messaging_module.current_action_state.is_empty() and not messaging_module.current_action_state.get("is_locomotion", false)
	var input_data = input_module.get_input_data()
	
	# 解耦控制模式：任何用户输入立即切换到用户控制模式
	var has_user_input = input_data.direction.length() > 0.1 or input_data.jump_pressed or input_data.jump_just_pressed
	if has_user_input:
		control_mode = PetData.ControlMode.USER
		# 不再强行清空服务器状态，而是标记用户正在干预
		# 物理引擎在 USER 模式下会自动优先响应本地输入
	else:
		# 没有用户输入时，根据服务器指令判断控制模式
		if is_server_moving or is_moving_to_click:
			control_mode = PetData.ControlMode.AI
		else:
			control_mode = PetData.ControlMode.USER  # 默认用户控制
	
	if is_moving_to_click:
		_handle_click_movement(delta)
	else:
		_handle_normal_physics(delta, input_data, is_doing_important_action)
	
	move_and_slide()
	_sync_animation_and_report(delta, is_doing_important_action)

func _handle_normal_physics(delta: float, input_data, is_doing_important_action: bool) -> void:
	physics_module.target_position = target_position
	physics_module.is_server_moving = is_server_moving
	physics_module.is_flying = is_flying
	var movement = physics_module.calculate_movement(input_data, global_position, delta)
	
	# 同步回状态，防止 calculate_movement 内部修改的状态被下一帧重置
	is_server_moving = physics_module.is_server_moving
	is_flying = physics_module.is_flying
	
	var is_proc = animation_module.proc_anim_type != PetData.ProcAnimType.NONE
	
	if not is_proc:
		physics_module.apply_physics(self, delta)
		physics_module.apply_movement(movement, self, delta, control_mode)
		
		# 解耦：战术逻辑只在AI控制模式下执行，用户控制时完全不介入
		# 这样EQS查询后的AI决策和战术逻辑不会影响用户手动控制
		if control_mode == PetData.ControlMode.AI:
			physics_module.process_tactical_logic(self, input_data)
		
		if not is_doing_important_action and current_anim_state != PetData.AnimState.JUMP:
			if physics_module.handle_jump(input_data, self):
				animation_module.set_anim_state(PetData.AnimState.JUMP)
	else:
		if is_flying or is_server_moving:
			physics_module.apply_movement(movement, self, delta, control_mode)

func _handle_click_movement(delta: float) -> void:
	var to_t = click_target_position - global_position
	to_t.y = 0
	if to_t.length() < arrival_distance:
		is_moving_to_click = false
		animation_module.set_anim_state(PetData.AnimState.IDLE)
		current_anim_state = PetData.AnimState.IDLE
		return
	velocity.x = to_t.normalized().x * click_move_speed
	velocity.z = to_t.normalized().z * click_move_speed
	rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z), 10.0 * delta)
	physics_module.apply_physics(self, delta)

func _sync_animation_and_report(delta: float, is_doing_important_action: bool) -> void:
	if is_on_floor() and current_anim_state == PetData.AnimState.JUMP and velocity.y <= 0:
		animation_module.set_anim_state(PetData.AnimState.IDLE)
	if not is_doing_important_action and current_anim_state != PetData.AnimState.JUMP:
		var h_speed = Vector2(velocity.x, velocity.z).length()
		var t_state = PetData.AnimState.IDLE
		var b_pos = 0.0
		
		# 修复：即使碰撞停止了速度，只要 AI 意图还在移动，就保持移动动画
		var is_trying_to_move = is_server_moving or is_moving_to_click
		
		if h_speed > 0.1 or is_trying_to_move:
			# 如果速度很低但正在尝试移动，强制使用 WALK 动画，防止原地踏步或切回 IDLE
			if h_speed < 0.5 and is_trying_to_move:
				t_state = PetData.AnimState.WALK
				b_pos = 0.3
			else:
				t_state = PetData.AnimState.RUN if h_speed > walk_speed * 1.1 else PetData.AnimState.WALK
				b_pos = clamp(h_speed / run_speed, 0.3, 1.0)
		
		if current_anim_state != t_state:
			animation_module.set_anim_state(t_state)
		if animation_tree:
			animation_tree.set("parameters/locomotion/blend_position", b_pos)
	physics_module.handle_collisions(self)
	physics_module.handle_physics_push(self)
	messaging_module.update_state_sync(delta, self, current_anim_state, interaction_module.is_dragging, is_executing_scene, animation_module.anim_state_to_string)

func _on_ground_clicked(pos: Vector3) -> void:
	click_target_position = pos
	is_moving_to_click = true
	_log("[Move] Clicked to: %s" % pos)

func _on_action_state_applied(state: Dictionary) -> void:
	_log("[Server] Executing: %s" % state.name)
	animation_module.switch_anim(state.name)
	var a = state.name.to_lower()
	if a == "fly":
		is_flying = true
		velocity.y = 8.0
	elif a == "jump":
		# 战术跳跃（空中前冲）仅在AI控制模式下使用（EQS/LLM指令）
		# 用户手动控制或点击移动不使用战术跳跃，保持解耦
		var is_tactical = control_mode == PetData.ControlMode.AI and is_server_moving
		physics_module.execute_jump(self, is_tactical)

## 🎯 P1：连续状态空间 - 客户端参数映射
func _on_status_updated(status: Dictionary) -> void:
	# 将服务端的连续状态值映射为动画树参数，实现平滑过渡
	var energy = status.get("energy", 100.0)  # 0-100
	var boredom = status.get("boredom", 0.0)  # 0-100
	var emotion = status.get("emotion", 0.5)  # 0.0-1.0

	# 归一化并设置BlendTree参数
	if animation_tree:
		# Energy影响整体动画的"活力"程度 (0.0 = 疲惫, 1.0 = 精力充沛)
		var normalized_energy = energy / 100.0
		animation_tree.set("parameters/energy_blend/blend_position", normalized_energy)

		# Emotion影响动画的情感表现 (0.0 = 悲伤, 1.0 = 快乐)
		animation_tree.set("parameters/emotion_blend/blend_position", emotion)

	_log("[Status] Updated continuous states - Energy: %.1f, Emotion: %.2f" % [energy, emotion])

func _on_ws_message(type: String, data: Dictionary) -> void:
	messaging_module.handle_ws_message(type, data, animation_tree)

func _on_eqs_result_ready(query_id: String, response: Dictionary) -> void:
	if ws_client:
		ws_client.send_message("eqs_result", response)
		_log("[EQS] Sent result for query: %s (%d results, %dms)" % [
			query_id,
			response.get("results", []).size(),
			response.get("execution_time_ms", 0)
		])
	else:
		_log("[EQS] Warning: Cannot send result, ws_client is null")

func _on_jump_triggered(_v: float) -> void:
	_log("[Action] Jump Triggered")
	messaging_module.send_interaction("jump", {}, global_position)

func _on_collision_detected(d: Dictionary) -> void:
	_log("[Collision] Hit: %s" % d.collider_name)
	messaging_module.send_interaction("collision", d, global_position)

func _on_anim_state_changed(_o: int, n: int) -> void:
	current_anim_state = n

func _on_procedural_finished(n: String) -> void:
	messaging_module.current_action_state = {}
	_log("[Action] Procedural Finished: %s" % n)

func _on_move_to_received(t: Vector3) -> void:
	target_position = t
	is_server_moving = true
	is_moving_to_click = false
	_log("[Server] New target received: %s (distance: %.2fm)" % [t, global_position.distance_to(t)])

func _on_position_set_received(p: Vector3) -> void:
	server_target_pos = p
	is_server_moving = false

func _on_scene_received(s: String, _d: Dictionary) -> void:
	if s == "welcome":
		_execute_welcome_scene()

func _on_dynamic_scene_received(steps: Array) -> void:
	_execute_dynamic_scene(steps)

func _on_eqs_query_received(d: Dictionary) -> void:
	# 确保上下文包含当前位置信息
	var query_id = d.get("query_id", "")
	if query_id.is_empty():
		_log("[EQS] Invalid query request: missing query_id")
		return

	_log("[EQS] Received query: %s, raw data: %s" % [query_id, str(d)])

	# 从消息中提取或构建上下文
	var data = d.get("data", {})
	var config = data.get("config", d.get("config", {}))
	var context = data.get("context", {})

	_log("[EQS] Extracted config: %s" % str(config))
	_log("[EQS] Extracted context: %s" % str(context))

	# 如果上下文为空或缺少必要信息，补充当前位置
	if context.is_empty():
		context = {
			"querier_position": [global_position.x, global_position.y, global_position.z],
			"target_position": null,
			"enemy_positions": []
		}

		# 从config中获取服务端提供的上下文信息
		if config.has("context"):
			var server_context = config.get("context", {})
			if server_context.has("target_position"):
				context["target_position"] = server_context.get("target_position")
			if server_context.has("enemy_positions"):
				context["enemy_positions"] = server_context.get("enemy_positions", [])
	else:
		# 确保上下文包含当前位置信息
		if not context.has("querier_position"):
			context["querier_position"] = [global_position.x, global_position.y, global_position.z]

	_log("[EQS] Final context: %s" % str(context))

	# 执行查询
	eqs_adapter.execute_query(query_id, config, context)
	_log("[EQS] Executing query: %s" % query_id)

func _log(msg: String) -> void:
	Logger.log("System", msg)

func _execute_dynamic_scene(steps: Array) -> void:
	is_executing_scene = true
	var tween = create_tween().set_parallel(false)
	for step in steps:
		match step.type:
			"fly":
				tween.tween_callback(func():
					is_flying = true
					animation_module.switch_anim("fly")  # 调用程序化动画
				)
				var target_v = Vector3(step.target[0], step.target[1], step.target[2])
				tween.tween_property(self, "global_position", target_v, step.duration).set_trans(Tween.TRANS_SINE)
			"land":
				var target_v = Vector3(step.target[0], step.target[1], step.target[2])
				tween.tween_property(self, "global_position", target_v, step.duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tween.tween_callback(func():
					is_flying = false
				)
			"anim":
				tween.tween_callback(func():
					animation_module.switch_anim(step.name)
				)
				tween.tween_interval(step.duration)
	tween.tween_callback(func():
		is_executing_scene = false
		animation_module.switch_anim("idle")
	)

func _execute_welcome_scene() -> void:
	var steps = [
		{"type": "fly", "target": [0, 1.8, -4], "duration": 1.2},
		{"type": "land", "target": [0, 0.3, -4], "duration": 0.5},
		{"type": "anim", "name": "wave", "duration": 2.5},
		{"type": "anim", "name": "flip", "duration": 2.0}
	]
	_execute_dynamic_scene(steps)
