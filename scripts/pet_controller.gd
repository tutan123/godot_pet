extends CharacterBody3D

## PetController.gd
## 增强版控制器：支持 Idle/Walk/Run 混合动画、Shift 加速以及服务端高频位置缓冲同步。

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")
@onready var ws_client = get_node_or_null("/root/Main/WebSocketClient")

@export_group("Movement Settings")
@export var walk_speed: float = 3.0
@export var run_speed: float = 7.0
@export var rotation_speed: float = 12.0
@export var jump_velocity: float = 6.5

# 内部状态
var target_position: Vector3
var is_server_moving: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var last_anim_state: String = ""

# 用于服务端高频同步的插值缓冲
var server_target_pos: Vector3
var use_high_freq_sync: bool = false

func _ready() -> void:
	target_position = global_position
	server_target_pos = global_position
	if ws_client:
		ws_client.message_received.connect(_on_ws_message)
	
	animation_tree.active = true

func _physics_process(delta: float) -> void:
	# 1. 重力
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# 2. 本地输入处理
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var is_running = Input.is_key_pressed(KEY_SHIFT)
	var camera = get_viewport().get_camera_3d()
	var direction = Vector3.ZERO
	
	if input_dir.length() > 0.1:
		is_server_moving = false
		use_high_freq_sync = false # 玩家操作时禁用服务端强制位移
		if camera:
			var cam_basis = camera.global_transform.basis
			direction = (cam_basis.x * input_dir.x + cam_basis.z * input_dir.y).normalized()
			direction.y = 0
	
	# 3. 速度与动画状态判定
	var move_vel = run_speed if is_running else walk_speed
	
	if direction.length() > 0.1:
		# --- 玩家手动控制 ---
		velocity.x = direction.x * move_vel
		velocity.z = direction.z * move_vel
		
		var target_rot = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rot, rotation_speed * delta)
		
		_switch_anim("run" if is_running else "walk")
		
	elif is_server_moving:
		# --- 服务端低频指令移动 (move_to) ---
		var to_target = (target_position - global_position)
		to_target.y = 0
		if to_target.length() > 0.2:
			var dir = to_target.normalized()
			velocity.x = dir.x * walk_speed
			velocity.z = dir.z * walk_speed
			rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), rotation_speed * delta)
			_switch_anim("walk")
		else:
			is_server_moving = false
			_switch_anim("idle")
			
	elif use_high_freq_sync:
		# --- 服务端高频强制同步 (插值平滑) ---
		global_position = global_position.lerp(server_target_pos, 0.2) # 插值平滑瞬移感
		_switch_anim("idle") # 高频同步通常不带步行动画，或者根据位移差判断
		
	else:
		# --- 停止 ---
		velocity.x = move_toward(velocity.x, 0, walk_speed * delta * 10)
		velocity.z = move_toward(velocity.z, 0, walk_speed * delta * 10)
		if is_on_floor():
			_switch_anim("idle")

	# 4. 跳跃
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		_switch_anim("jump")

	move_and_slide()

func _switch_anim(anim_name: String) -> void:
	if last_anim_state == anim_name and anim_name != "jump":
		return
	
	if playback:
		playback.travel(anim_name)
		last_anim_state = anim_name

func _on_ws_message(type: String, data: Dictionary) -> void:
	match type:
		"bt_output":
			if data.has("action"):
				_switch_anim(data["action"].to_lower())
		"move_to":
			if data.has("target"):
				var t = data["target"]
				target_position = Vector3(t[0], t[1], t[2])
				is_server_moving = true
		"set_position":
			# 用于高频位置更新
			if data.has("pos"):
				var p = data["pos"]
				server_target_pos = Vector3(p[0], p[1], p[2])
				use_high_freq_sync = true
				is_server_moving = false