class_name GestureRecognizer
extends Node

# 手势识别配置
@export var pinch_threshold: float = 0.1
@export var rotate_threshold: float = 0.1
@export var swipe_threshold: float = 50.0
@export var long_press_threshold: float = 0.5

# 手势状态
var initial_distance: float = 0.0
var last_distance: float = 0.0
var initial_angle: float = 0.0
var last_angle: float = 0.0
var initial_center: Vector2 = Vector2.ZERO
var last_center: Vector2 = Vector2.ZERO

# 多指跟踪
var touch_history: Array = []
var max_history_size: int = 10

# 信号
signal gesture_detected(gesture_type: String, gesture_data: Dictionary)

func _ready():
    reset()

func reset():
    initial_distance = 0.0
    last_distance = 0.0
    initial_angle = 0.0
    last_angle = 0.0
    initial_center = Vector2.ZERO
    last_center = Vector2.ZERO
    touch_history.clear()

# 更新多指触摸
func update_multi_touch(touch_points: Array, center: Vector2, distance: float):
    # 记录历史
    touch_history.append({
        "points": touch_points.duplicate(),
        "center": center,
        "distance": distance,
        "time": Time.get_ticks_msec()
    })

    if touch_history.size() > max_history_size:
        touch_history.pop_front()

    # 计算角度
    var angle = 0.0
    if touch_points.size() >= 2:
        var p1 = touch_points[0].position
        var p2 = touch_points[1].position
        var delta = p2 - p1
        angle = atan2(delta.y, delta.x)

    # 初始化
    if initial_distance == 0.0:
        initial_distance = distance
        initial_angle = angle
        initial_center = center
        last_distance = distance
        last_angle = angle
        last_center = center
        return

    # 检测手势
    _detect_pinch_gesture(distance)
    _detect_rotate_gesture(angle)
    _detect_pan_gesture(center)

    last_distance = distance
    last_angle = angle
    last_center = center

# 检测捏合手势
func _detect_pinch_gesture(current_distance: float):
    if initial_distance == 0.0:
        return

    var scale = current_distance / initial_distance
    var delta_scale = current_distance / last_distance

    # 检查是否超过阈值
    if abs(scale - 1.0) > pinch_threshold:
        var gesture_data = {
            "scale": scale,
            "delta_scale": delta_scale,
            "initial_distance": initial_distance,
            "current_distance": current_distance,
            "center": last_center
        }

        gesture_detected.emit("pinch", gesture_data)

# 检测旋转手势
func _detect_rotate_gesture(current_angle: float):
    if initial_distance == 0.0:
        return

    var angle_diff = current_angle - initial_angle

    # 标准化角度差
    while angle_diff > PI:
        angle_diff -= 2 * PI
    while angle_diff < -PI:
        angle_diff += 2 * PI

    # 检查是否超过阈值
    if abs(angle_diff) > rotate_threshold:
        var gesture_data = {
            "angle": angle_diff,
            "initial_angle": initial_angle,
            "current_angle": current_angle,
            "center": last_center
        }

        gesture_detected.emit("rotate", gesture_data)

# 检测平移手势
func _detect_pan_gesture(current_center: Vector2):
    if initial_center == Vector2.ZERO:
        return

    var delta = current_center - last_center

    if delta.length() > 1.0:  # 最小移动阈值
        var gesture_data = {
            "delta": delta,
            "current_center": current_center,
            "initial_center": initial_center,
            "velocity": _calculate_velocity()
        }

        gesture_detected.emit("pan", gesture_data)

# 计算手势速度
func _calculate_velocity() -> Vector2:
    if touch_history.size() < 2:
        return Vector2.ZERO

    var recent = touch_history.back()
    var previous = touch_history[touch_history.size() - 2]

    var time_diff = (recent.time - previous.time) / 1000.0  # 转换为秒
    if time_diff <= 0:
        return Vector2.ZERO

    var position_diff = recent.center - previous.center
    return position_diff / time_diff

# 单指手势识别
func recognize_single_touch(touch_data: Dictionary):
    var duration = touch_data.get("duration", 0.0)
    var distance = touch_data.get("distance", 0.0)
    var position = touch_data.get("position", Vector2.ZERO)

    # 长按识别
    if duration > long_press_threshold:
        var gesture_data = {
            "position": position,
            "duration": duration
        }
        gesture_detected.emit("long_press", gesture_data)

    # 滑动识别
    elif distance > swipe_threshold:
        var direction = touch_data.get("direction", Vector2.ZERO)
        var gesture_data = {
            "start_position": touch_data.get("start_position", Vector2.ZERO),
            "end_position": position,
            "direction": direction,
            "distance": distance,
            "velocity": touch_data.get("velocity", Vector2.ZERO)
        }
        gesture_detected.emit("swipe", gesture_data)

# 双击识别
func recognize_double_tap(first_tap: Dictionary, second_tap: Dictionary):
    var time_diff = second_tap.time - first_tap.time
    var distance = first_tap.position.distance_to(second_tap.position)

    # 检查双击条件：时间间隔短，距离近
    if time_diff < 300 and distance < 50:  # 300ms内，50像素内
        var gesture_data = {
            "first_tap": first_tap,
            "second_tap": second_tap,
            "center": (first_tap.position + second_tap.position) / 2,
            "time_diff": time_diff
        }
        gesture_detected.emit("double_tap", gesture_data)

# 获取手势配置
func get_gesture_config() -> Dictionary:
    return {
        "pinch_threshold": pinch_threshold,
        "rotate_threshold": rotate_threshold,
        "swipe_threshold": swipe_threshold,
        "long_press_threshold": long_press_threshold,
        "max_history_size": max_history_size
    }

# 设置手势配置
func set_gesture_config(config: Dictionary):
    if config.has("pinch_threshold"):
        pinch_threshold = config.pinch_threshold
    if config.has("rotate_threshold"):
        rotate_threshold = config.rotate_threshold
    if config.has("swipe_threshold"):
        swipe_threshold = config.swipe_threshold
    if config.has("long_press_threshold"):
        long_press_threshold = config.long_press_threshold
    if config.has("max_history_size"):
        max_history_size = config.max_history_size

# 获取手势历史
func get_gesture_history() -> Array:
    return touch_history.duplicate()

# 清除手势历史
func clear_history():
    touch_history.clear()