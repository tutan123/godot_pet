# logger.gd
extends RefCounted

## 机器人项目专用日志工具类
## 通过 PetLoggerScript.new() 实例化后使用

const LOG_COOLDOWN_MS = 3000
var _log_history: Dictionary = {}

func info(category: String, message: String, force: bool = false) -> void:
	var now = Time.get_ticks_msec()

	# 去重逻辑
	if not force and _log_history.has(category + message) and now - _log_history[category + message] < LOG_COOLDOWN_MS:
		return

	_log_history[category + message] = now

	var unix_time = Time.get_unix_time_from_system()
	var datetime = Time.get_datetime_dict_from_unix_time(unix_time)
	var milliseconds = int((unix_time - int(unix_time)) * 1000)
	var time_str = "%02d:%02d:%02d.%03d" % [datetime.hour, datetime.minute, datetime.second, milliseconds]

	print("[%s] [%s] %s" % [time_str, category, message])

func warn(category: String, message: String) -> void:
	info(category, "WARN: " + message, true)

func error(category: String, message: String) -> void:
	info(category, "ERROR: " + message, true)

func perf(category: String, message: String) -> void:
	info(category, "PERF: " + message, true)
