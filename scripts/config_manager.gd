extends Node

## config_manager.gd
## 配置管理模块：负责保存和加载应用配置

const CONFIG_FILE_PATH = "user://godot_pet_config.cfg"

var websocket_url: String = "ws://localhost:8080"
var asr_websocket_url: String = "ws://localhost:8000/api/v1/realtime"

func _ready() -> void:
	load_config()

func save_config() -> void:
	var config = ConfigFile.new()
	config.set_value("server", "websocket_url", websocket_url)
	config.set_value("asr", "websocket_url", asr_websocket_url)
	
	var err = config.save(CONFIG_FILE_PATH)
	if err != OK:
		print("保存配置失败: ", err)
	else:
		print("配置已保存")

func load_config() -> void:
	var config = ConfigFile.new()
	var err = config.load(CONFIG_FILE_PATH)
	
	if err != OK:
		# 配置文件不存在，使用默认值
		print("使用默认配置")
		return
	
	websocket_url = config.get_value("server", "websocket_url", "ws://localhost:8080")
	asr_websocket_url = config.get_value("asr", "websocket_url", "ws://localhost:8000/api/v1/realtime")
	
	print("配置已加载: WebSocket=", websocket_url, ", ASR=", asr_websocket_url)
