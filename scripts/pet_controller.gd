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

var target_position: Vector3
var is_server_moving: bool = false
var is_flying: bool = false
var is_executing_scene: bool = false
var last_floor_collider: String = ""
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_anim_state: int = PetData.AnimState.IDLE
var proc_anim_type: int = PetData.ProcAnimType.NONE
var proc_time: float = 0.0
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
	
	if ws_client: ws_client.message_received.connect(_on_ws_message)
	physics_module.jump_triggered.connect(_on_jump_triggered)
	physics_module.collision_detected.connect(_on_collision_detected)
	animation_module.anim_state_changed.connect(_on_anim_state_changed)
	messaging_module.action_state_applied.connect(_on_action_state_applied)
	messaging_module.move_to_received.connect(_on_move_to_received)
	messaging_module.position_set_received.connect(_on_position_set_received)
	messaging_module.scene_received.connect(_on_scene_received)
	messaging_module.dynamic_scene_received.connect(_on_dynamic_scene_received)
	
	if animation_tree: animation_tree.active = true
	_log("[System] Robot Initialized and Ready.")

func _physics_process(delta: float) -> void:
	proc_time += delta
	animation_module.update_state_vars(current_anim_state, proc_anim_type, proc_time, 0.0, 0.0, 0.0, 0.0, current_action_state)
	messaging_module.update_state_sync(delta, self, current_anim_state, interaction_module.is_dragging, is_executing_scene, _anim_state_to_string)
	
	if interaction_module.is_dragging:
		is_executing_scene = false
		interaction_module.handle_dragging(delta, self, mesh_root, proc_time)
		return

	if is_executing_scene: return

	var input_data = input_module.get_input_data()
	physics_module.target_position = target_position
	physics_module.is_server_moving = is_server_moving
	physics_module.is_flying = is_flying
	var movement_data = physics_module.calculate_movement(input_data, global_position, delta)
	
	physics_module.apply_physics(movement_data, self, delta)
	physics_module.apply_movement(movement_data, self, delta)
	
	if physics_module.handle_jump(input_data, self):
		animation_module.set_anim_state(PetData.AnimState.JUMP)
	
	move_and_slide()
	
	# 地面检测 Log
	if is_on_floor() and get_slide_collision_count() > 0:
		var coll = get_last_slide_collision()
		if coll and coll.get_collider():
			var floor_name = coll.get_collider().name
			if floor_name != last_floor_collider:
				_log("[Physics] Stepped onto: %s" % floor_name)
				last_floor_collider = floor_name

	physics_module.handle_collisions(self)
	
	# 状态切换 Log
	if is_on_floor() and movement_data.target_anim_state != current_anim_state:
		_log("[Anim] State Change: %s -> %s" % [_anim_state_to_string(current_anim_state), _anim_state_to_string(movement_data.target_anim_state)])
		animation_module.set_anim_state(movement_data.target_anim_state)
		current_anim_state = movement_data.target_anim_state

func _process(delta: float) -> void:
	animation_module.apply_procedural_fx(delta, interaction_module.is_dragging)

func _on_ws_message(type: String, data: Dictionary) -> void:
	messaging_module.handle_ws_message(type, data, animation_tree)

func _on_jump_triggered(_v): 
	_log("[Action] Jump Triggered")
	messaging_module.send_interaction("jump", {}, global_position)

func _on_collision_detected(data): 
	_log("[Collision] Hit: %s" % data.collider_name)
	messaging_module.send_interaction("collision", data, global_position)

func _on_anim_state_changed(_o, n): current_anim_state = n

func _on_action_state_applied(state):
	if is_executing_scene: return
	if not state is Dictionary or state.is_empty() or not state.has("name"):
		return
	_log("[Server] Executing Action: %s" % state.name)
	animation_module.switch_anim(state.name)

func _on_move_to_received(target): target_position = target; is_server_moving = true

func _on_position_set_received(pos: Vector3) -> void:
	server_target_pos = pos
	use_high_freq_sync = true
	is_server_moving = false

func _on_scene_received(scene_name, _d): if scene_name == "welcome": _execute_welcome_scene()

func _on_dynamic_scene_received(steps): _execute_dynamic_scene(steps)

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
