extends Node

## scene_object_sync.gd
## 场景对象同步模块：定期上报场景中的对象位置（如小球）

const Logger = preload("res://scripts/logger.gd")

## 节点引用
var ws_client: Node
var scene_objects: Array[Node3D] = []

## 同步配置
var sync_interval: float = 0.5  # 每0.5秒同步一次
var sync_timer: float = 0.0

## 对象配置
var tracked_objects: Dictionary = {}  # {node_path: object_id}

func _ready():
	# 查找场景中的对象
	_find_scene_objects()

func _find_scene_objects():
	# 查找所有需要同步的对象
	var main = get_node_or_null("/root/Main")
	if not main:
		return
	
	# 使用 find_child 进行更稳健的递归查找（因为节点层级可能变化）
	# 1. 查找小球
	var ball = main.find_child("Ball", true, false)
	if ball:
		scene_objects.append(ball)
		tracked_objects[ball.get_path()] = "ball"
		Logger.log("SceneObjectSync", "Registered ball for sync at path: %s" % ball.get_path())

	# 2. 查找主摄像机
	var camera = get_viewport().get_camera_3d()
	if camera:
		scene_objects.append(camera)
		tracked_objects[camera.get_path()] = "camera"
		Logger.log("SceneObjectSync", "Registered camera for sync")
	
	# 3. 查找静态目标点
	var stage = main.find_child("Stage", true, false)
	if stage:
		scene_objects.append(stage)
		tracked_objects[stage.get_path()] = "stage"
		Logger.log("SceneObjectSync", "Registered stage for sync")
	
	var ramp = main.find_child("Ramp", true, false)
	if ramp:
		scene_objects.append(ramp)
		tracked_objects[ramp.get_path()] = "ramp"
		Logger.log("SceneObjectSync", "Registered ramp for sync")

func _process(delta: float):
	if not ws_client:
		return
	
	sync_timer += delta
	if sync_timer >= sync_interval:
		sync_timer = 0.0
		_sync_objects()

func _sync_objects():
	if scene_objects.is_empty():
		return
	
	var objects: Array[Dictionary] = []
	
	for obj in scene_objects:
		if not is_instance_valid(obj):
			continue
		
		var obj_id = tracked_objects.get(obj.get_path(), "unknown")
		var pos = obj.global_position
		
		objects.append({
			"id": obj_id,
			"position": [pos.x, pos.y, pos.z],
			"rotation": [obj.rotation.x, obj.rotation.y, obj.rotation.z]
		})
	
	if objects.size() > 0:
		ws_client.send_message("scene_object_sync", {
			"objects": objects
		})
		# print("[SceneObjectSync] Synced %d objects" % objects.size())