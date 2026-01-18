class_name Logger
extends Node

# 统一的日志工具类，提供带毫秒精度的时间戳
# 使用示例：
# Logger.log("System", "Navigation mesh ready")
# Logger.warn("Physics", "Collision detected")
# Logger.error("Network", "Connection failed")

const LOG_COOLDOWN_MS = 3000
var log_history: Dictionary = {}

static func log(category: String, message: String, force: bool = false) -> void:
	var now = Time.get_ticks_msec()

	# 去重逻辑（除非强制输出）
	if not force and log_history.has(message) and now - log_history[message] < LOG_COOLDOWN_MS:
		return

	log_history[message] = now

	# 生成带毫秒的时间戳
	var unix_time = Time.get_unix_time_from_system()
	var datetime = Time.get_datetime_dict_from_unix_time(unix_time)
	var milliseconds = int((unix_time - int(unix_time)) * 1000)
	var time_str = "%02d:%02d:%02d.%03d" % [datetime.hour, datetime.minute, datetime.second, milliseconds]

	print("[%s] [%s] %s" % [time_str, category, message])

static func warn(category: String, message: String) -> void:
	log(category, "WARN: " + message, true)  # 警告总是输出

static func error(category: String, message: String) -> void:
	log(category, "ERROR: " + message, true)  # 错误总是输出

# 兼容旧的日志函数
static func info(category: String, message: String) -> void:
	log(category, message)

# 带对象的日志（自动转换为字符串）
static func log_object(category: String, message: String, obj: Variant) -> void:
	var obj_str = str(obj)
	log(category, message + ": " + obj_str)

# 性能日志（总是输出）
static func perf(category: String, message: String) -> void:
	log(category, "PERF: " + message, true)