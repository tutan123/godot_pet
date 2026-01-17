## pet_data.gd
## 数据结构定义模块：包含动画状态枚举、程序化动画类型枚举和辅助数据结构

## 动画状态枚举
enum AnimState {
	IDLE,
	WALK,
	RUN,
	JUMP,
	WAVE
}

## 程序化动画类型
enum ProcAnimType {
	NONE,
	WAVE,
	SPIN,
	BOUNCE,
	FLY,
	ROLL,
	SHAKE,
	FLIP,
	DANCE
}

## 控制模式枚举 - 解耦用户控制与AI战术
enum ControlMode {
	USER,      # 用户手动控制模式 - 战术逻辑完全不介入
	AI         # AI控制模式 - 允许战术逻辑介入（EQS查询后的AI行为）
}

## 移动数据类
class MovementData:
	var direction: Vector3
	var speed: float
	var is_running: bool
	var target_anim_state: int  # AnimState 枚举值
	var tilt_target: float
	
	func _init():
		direction = Vector3.ZERO
		speed = 0.0
		is_running = false
		target_anim_state = 0  # AnimState.IDLE
		tilt_target = 0.0

## 输入数据类
class InputData:
	var direction: Vector2
	var is_running: bool
	var is_typing: bool
	var jump_pressed: bool
	var jump_just_pressed: bool
	
	func _init():
		direction = Vector2.ZERO
		is_running = false
		is_typing = false
		jump_pressed = false
		jump_just_pressed = false
