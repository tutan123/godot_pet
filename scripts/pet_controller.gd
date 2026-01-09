extends CharacterBody3D

## PetController.gd
## 增强版控制器：支持 Idle/Walk/Run、鼠标点击/拖拽交互、程序化动作及服务端同步。

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")
@onready var ws_client = get_node_or_null("/root/Main/WebSocketClient")
@onready var mesh_root = $Player

@export_group("Movement Settings")
@export var walk_speed: float = 3.0
@export var run_speed: float = 7.0
@export var rotation_speed: float = 12.0
@export var jump_velocity: float = 6.5

@export_group("Interaction Settings")
@export var drag_height: float = 1.5

# 内部状态
var target_position: Vector3
var is_server_moving: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var last_anim_state: String = ""

# 交互状态
var is_dragging: bool = false
var drag_target_pos: Vector3

# 程序化动作变量
var proc_time: float = 0.0
var shake_intensity: float = 0.0 # 抖动强度
var tilt_angle: float = 0.0 # 倾斜角度（跑步时前倾）

# 用于服务端高频同步的插值缓冲
var server_target_pos: Vector3
var use_high_freq_sync: bool = false

func _ready() -> void:
	target_position = global_position
	server_target_pos = global_position
	if ws_client:
		ws_client.message_received.connect(_on_ws_message)
	
	animation_tree.active = true
	input_ray_pickable = true

func _input_event(camera: Camera3D, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_clicked()
				is_dragging = true
				_send_interaction("drag_start", position)
			else:
				is_dragging = false
				_send_interaction("drag_end", position)

func _physics_process(delta: float) -> void:
	proc_time += delta
	
	# 1. 拖拽逻辑处理
	if is_dragging:
		_handle_dragging(delta)
		return

	# 2. 重力
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# 3. 本地输入处理 (WASD)
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var is_running = Input.is_key_pressed(KEY_SHIFT)
	var camera = get_viewport().get_camera_3d()
	var direction = Vector3.ZERO
	
	if input_dir.length() > 0.1:
		is_server_moving = false
		use_high_freq_sync = false
		if camera:
			var cam_basis = camera.global_transform.basis
			direction = (cam_basis.x * input_dir.x + cam_basis.z * input_dir.y).normalized()
			direction.y = 0
	
	# 4. 速度与动画状态判定
	var move_vel = run_speed if is_running else walk_speed
	
	if direction.length() > 0.1:
		velocity.x = direction.x * move_vel
		velocity.z = direction.z * move_vel
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), rotation_speed * delta)
		_switch_anim("run" if is_running else "walk")
		# 程序化前倾
		tilt_angle = lerp(tilt_angle, 0.2 if is_running else 0.1, 5.0 * delta)
		
	elif is_server_moving:
		var to_target = (target_position - global_position)
		to_target.y = 0
		if to_target.length() > 0.2:
			var dir = to_target.normalized()
			velocity.x = dir.x * walk_speed
			velocity.z = dir.z * walk_speed
			rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), rotation_speed * delta)
			_switch_anim("walk")
			tilt_angle = lerp(tilt_angle, 0.1, 5.0 * delta)
		else:
			is_server_moving = false
			_switch_anim("idle")
			tilt_angle = lerp(tilt_angle, 0.0, 5.0 * delta)
			
	elif use_high_freq_sync:
		global_position = global_position.lerp(server_target_pos, 0.2)
		_switch_anim("idle")
		tilt_angle = lerp(tilt_angle, 0.0, 5.0 * delta)
		
	else:
		velocity.x = move_toward(velocity.x, 0, walk_speed * delta * 10)
		velocity.z = move_toward(velocity.z, 0, walk_speed * delta * 10)
		if is_on_floor():
			_switch_anim("idle")
		tilt_angle = lerp(tilt_angle, 0.0, 5.0 * delta)

	# 5. 跳跃
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		_switch_anim("jump")

	move_and_slide()
	
	# 6. 应用程序化动画 (叠加效果)
	_apply_procedural_fx(delta)

func _handle_dragging(delta: float) -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var drop_plane = Plane(Vector3.UP, drag_height)
	var intersect_pos = drop_plane.intersects_ray(ray_origin, ray_dir)
	
	if intersect_pos:
		global_position = global_position.lerp(intersect_pos, 20.0 * delta)
		velocity = Vector3.ZERO
		_switch_anim("jump")
		# 拖拽时的程序化摆动
		mesh_root.rotation.z = sin(proc_time * 10.0) * 0.2

func _on_clicked() -> void:
	_send_interaction("click", global_position)
	# 本地立即反馈：缩小一下再弹起
	var tween = create_tween()
	tween.tween_property(mesh_root, "scale", Vector3(1.2, 0.8, 1.2) * 0.3, 0.1)
	tween.tween_property(mesh_root, "scale", Vector3(1.0, 1.0, 1.0) * 0.3, 0.2).set_trans(Tween.TRANS_BOUNCE)

func _apply_procedural_fx(delta: float) -> void:
	# A. 基础呼吸感
	var idle_float = sin(proc_time * 2.0) * 0.05 if last_anim_state == "idle" else 0.0
	mesh_root.position.y = idle_float
	
	# B. 点击后的抖动衰减
	if shake_intensity > 0:
		mesh_root.position.x = (randf() - 0.5) * shake_intensity * 0.2
		mesh_root.position.z = (randf() - 0.5) * shake_intensity * 0.2
		shake_intensity = move_toward(shake_intensity, 0, delta * 4.0)
	else:
		mesh_root.position.x = move_toward(mesh_root.position.x, 0, delta)
		mesh_root.position.z = move_toward(mesh_root.position.z, 0, delta)
	
	# C. 运动时的身体前倾
	mesh_root.rotation.x = tilt_angle
	
	# D. 拖拽结束后的姿态恢复
	if not is_dragging:
		mesh_root.rotation.z = move_toward(mesh_root.rotation.z, 0, delta * 5.0)

func _switch_anim(anim_name: String) -> void:
	if last_anim_state == anim_name and anim_name != "jump":
		return
	if playback:
		playback.travel(anim_name)
		last_anim_state = anim_name

func _send_interaction(action: String, pos: Vector3) -> void:
	if ws_client and ws_client.is_connected:
		ws_client.send_message("interaction", {
			"action": action,
			"position": [pos.x, pos.y, pos.z]
		})

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
			if data.has("pos"):
				var p = data["pos"]
				server_target_pos = Vector3(p[0], p[1], p[2])
				use_high_freq_sync = true
				is_server_moving = false
