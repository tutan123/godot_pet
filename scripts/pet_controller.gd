extends CharacterBody3D

## PetController.gd
## 控制萌宠的身体动作、表情，并支持 WASD 手动控制和服务端指令控制。

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var ws_client = get_node("/root/Main/WebSocketClient")

@export var move_speed: float = 4.0
@export var run_speed: float = 7.0
@export var rotation_speed: float = 10.0
@export var jump_velocity: float = 5.0

# 状态变量
var target_position: Vector3
var is_server_moving: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	target_position = global_position
	# 监听 WebSocket 消息
	if ws_client:
		ws_client.message_received.connect(_on_ws_message)
	
	if animation_tree:
		animation_tree.active = true

func _physics_process(delta: float) -> void:
	# 1. 应用重力
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# 2. 获取输入（WASD）
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var camera = get_viewport().get_camera_3d()
	var direction = Vector3.ZERO
	
	if input_dir.length() > 0:
		# 停止服务端自动移动，切换到手动模式
		is_server_moving = false
		
		# 基于相机视角的移动方向
		if camera:
			var cam_basis = camera.global_transform.basis
			direction = (cam_basis.x * input_dir.x + cam_basis.z * input_dir.y).normalized()
			direction.y = 0
			direction = direction.normalized()
	
	# 3. 处理移动逻辑
	var current_horizontal_speed = Vector2(velocity.x, velocity.z).length()
	
	if direction.length() > 0:
		# 手动移动
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		
		# 转向
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)
	elif is_server_moving:
		# 服务端下发的自动移动
		var to_target = (target_position - global_position)
		to_target.y = 0
		
		if to_target.length() > 0.1:
			var dir = to_target.normalized()
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
			
			var target_rot = atan2(dir.x, dir.z)
			rotation.y = lerp_angle(rotation.y, target_rot, rotation_speed * delta)
		else:
			velocity.x = 0
			velocity.z = 0
			is_server_moving = false
	else:
		# 停止移动
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	# 4. 跳跃逻辑
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		if animation_tree:
			animation_tree.set("parameters/state/transition_request", "air")

	move_and_slide()
	
	# 5. 更新动画混合参数
	_update_animations(delta)

func _update_animations(_delta: float) -> void:
	if not animation_tree: return
	
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	
	if is_on_floor():
		animation_tree.set("parameters/state/transition_request", "ground")
		
		# 混合 Idle 和 Walk
		var speed_blend = clamp(horizontal_speed / move_speed, 0.0, 1.0)
		animation_tree.set("parameters/speed_blend/blend_amount", speed_blend)
		
		# 混合 Walk 和 Run (如果有更高速度)
		var run_blend = clamp((horizontal_speed - move_speed) / (run_speed - move_speed), 0.0, 1.0)
		animation_tree.set("parameters/run_blend/blend_amount", run_blend)
	else:
		animation_tree.set("parameters/state/transition_request", "air")

func _on_ws_message(type: String, data: Dictionary) -> void:
	match type:
		"bt_output":
			_handle_bt_output(data)
		"move_to":
			_handle_move_to(data)

func _handle_bt_output(data: Dictionary) -> void:
	if data.has("action"):
		var action = data["action"].to_lower()
		# 这里可以根据需要触发特定动作动画
		pass

func _handle_move_to(data: Dictionary) -> void:
	if data.has("target"):
		var t = data["target"]
		target_position = Vector3(t[0], t[1], t[2])
		is_server_moving = true
