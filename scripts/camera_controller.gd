extends Node3D

## CameraController.gd
## 实现第三人称视角控制，支持鼠标右键旋转和滚轮缩放。

## 目标节点路径（通常是 Pet 角色）
@export var target_path: NodePath

## 鼠标旋转灵敏度（值越大，旋转越快）
@export var mouse_sensitivity: float = 0.3

## 滚轮缩放速度（每次滚轮滚动的距离变化）
@export var zoom_speed: float = 0.5

## 最小缩放距离（拉近时的最近距离，单位：米）
@export var min_zoom: float = 1.0

## 最大缩放距离（拉远时的最远距离，单位：米）
@export var max_zoom: float = 12.0

## 相机跟随目标的平滑速度（值越大，跟随越快）
@export var follow_speed: float = 5.0

## 角色高度（单位：米）- 用于计算相机位置，根据实际模型高度调整
## 如果模型比机器人矮，需要相应减小这个值（例如：人形模型约 1.0-1.2m，机器人可能 1.5-1.8m）
@export var character_height: float = 0.2

## 越肩视角偏移：拉近时相机向右侧偏移的距离（相对于角色高度的比例）
@export var shoulder_offset_ratio: float = 0.35

## 越肩视角高度比例：拉近时相机高度相对于角色高度的比例（0.0=脚部, 1.0=头顶）
## 0.85 表示在角色 85% 高度处（约肩膀/头部位置）
@export var shoulder_height_ratio: float = 0.85

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var target: Node3D = get_node_or_null(target_path)

## 相机俯仰角（X轴旋转，负数表示向下看，正数表示向上看）
## 范围：-80.0（最向下）到 20.0（最向上）
var rotation_x: float = -35.0

## 相机水平旋转角（Y轴旋转，控制左右视角）
var rotation_y: float = 0.0

func _ready() -> void:
	# 初始化相机旋转角度
	if spring_arm:
		spring_arm.rotation_degrees.x = rotation_x  # 设置俯仰角（向下看的角度）
		rotation_degrees.y = rotation_y  # 设置水平旋转角
	
	# 如果没有手动指定目标，尝试自动寻找名为 "Pet" 的节点
	if not target:
		target = get_parent().find_child("Pet")
	
	# 关键修复：将目标角色添加到 SpringArm3D 的排除列表
	# 这样当角色转向摄像头（如按S键）时，相机的防穿模探测射线会忽略角色本身
	if spring_arm and target:
		spring_arm.add_excluded_object(target.get_rid())

func _input(event: InputEvent) -> void:
	# 鼠标右键拖拽旋转视角
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		# 水平旋转（左右移动鼠标）
		rotation_y -= event.relative.x * mouse_sensitivity
		# 垂直旋转（上下移动鼠标）
		rotation_x -= event.relative.y * mouse_sensitivity
		# 限制俯仰角范围：-80度（最向下）到 20度（最向上）
		rotation_x = clamp(rotation_x, -80.0, 20.0)
		
		# 应用旋转角度
		rotation_degrees.y = rotation_y
		if spring_arm:
			spring_arm.rotation_degrees.x = rotation_x

	# 滚轮缩放相机距离
	if event is InputEventMouseButton:
		# 如果输入框有焦点，不处理缩放（避免在输入时误触发）
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return
		
		# 只处理滚轮事件，忽略其他鼠标按钮（修复S键bug）
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# 滚轮向上：拉近相机（减小距离）
			spring_arm.spring_length = clamp(spring_arm.spring_length - zoom_speed, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# 滚轮向下：拉远相机（增加距离）
			spring_arm.spring_length = clamp(spring_arm.spring_length + zoom_speed, min_zoom, max_zoom)

func _physics_process(delta: float) -> void:
	if target:
		# 1. 计算越肩视角的权重：拉得越近，越肩效果越明显
		# 当 spring_length 为 min_zoom 时权重为 1.0，当达到一定距离（如 4.0）后权重归 0
		var shoulder_weight = clamp((4.0 - spring_arm.spring_length) / (4.0 - min_zoom), 0.0, 1.0)
		
		# 2. 基于角色高度计算实际偏移值
		var shoulder_offset = character_height * shoulder_offset_ratio
		var shoulder_height = character_height * shoulder_height_ratio
		var far_height = character_height * 1.2  # 远距离时稍微高一点
		
		# 3. 动态调整 SpringArm3D 的本地位置，实现越肩偏移
		# X轴：向右偏移实现越肩；Y轴：根据缩放调整高度（近时在肩膀高度，远时稍高）
		var current_x_offset = shoulder_offset * shoulder_weight
		var current_y_offset = lerp(far_height, shoulder_height, shoulder_weight)
		spring_arm.position = Vector3(current_x_offset, current_y_offset, 0)
		
		# 4. 计算目标跟随位置：基于角色高度的中心位置（约 50% 高度，即腰部）
		var target_height_offset = character_height * 0.5
		var target_pos = target.global_position + Vector3(0, target_height_offset, 0)
		
		# 5. 平滑跟随目标位置
		global_position = global_position.lerp(target_pos, follow_speed * delta)
