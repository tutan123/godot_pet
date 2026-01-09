extends Node3D

## CameraController.gd
## 实现第三人称视角控制，支持鼠标右键旋转和滚轮缩放。

@export var target_path: NodePath
@export var mouse_sensitivity: float = 0.3
@export var zoom_speed: float = 0.5
@export var min_zoom: float = 2.0
@export var max_zoom: float = 12.0
@export var follow_speed: float = 5.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var target: Node3D = get_node_or_null(target_path)

var rotation_x: float = -20.0 # 初始俯视角度
var rotation_y: float = 0.0

func _ready() -> void:
	# 设置初始旋转
	if spring_arm:
		spring_arm.rotation_degrees.x = rotation_x
		rotation_degrees.y = rotation_y
	
	# 如果没有手动指定目标，尝试寻找名为 "Pet" 的节点
	if not target:
		target = get_parent().find_child("Pet")

func _input(event: InputEvent) -> void:
	# 鼠标右键旋转
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		rotation_y -= event.relative.x * mouse_sensitivity
		rotation_x -= event.relative.y * mouse_sensitivity
		rotation_x = clamp(rotation_x, -80.0, 20.0) # 限制俯仰角
		
		rotation_degrees.y = rotation_y
		if spring_arm:
			spring_arm.rotation_degrees.x = rotation_x

	# 滚轮缩放
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			spring_arm.spring_length = clamp(spring_arm.spring_length - zoom_speed, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			spring_arm.spring_length = clamp(spring_arm.spring_length + zoom_speed, min_zoom, max_zoom)

func _physics_process(delta: float) -> void:
	if target:
		# 平滑跟随目标位置
		var target_pos = target.global_position + Vector3(0, 0.5, 0) # 稍微偏移到宠物中心
		global_position = global_position.lerp(target_pos, follow_speed * delta)
