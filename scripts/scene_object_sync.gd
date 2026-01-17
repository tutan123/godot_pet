extends Node

## scene_object_sync.gd
## 场景对象同步模块：定期上报场景中的对象位置（如小球）

## 节点引用
var ws_client: Node
var scene_objects: Array[Node3D] = []

## 同步配置
var sync_interval: float = 0.5  # 每0.5秒同步一次
var sync_timer: float = 0.0

## 对象配置
var tracked_objects: Dictionary = {}  # {node_path: object_id}

func _ready():
	# 查找场景中的小球
	_find_scene_objects()

func _find_scene_objects():
	# 查找所有需要同步的对象
	var main = get_node_or_null("/root/Main")
	if not main:
		return
	
	# 1. 查找小球
	var ball = main.get_node_or_null("PhysicsTest/Ball")
	if ball:
		scene_objects.append(ball)
		tracked_objects[ball.get_path()] = "ball"
		print("[SceneObjectSync] Registered ball for sync")

	# 2. 查找主摄像机
	var camera = get_viewport().get_camera_3d()
	if camera:
		scene_objects.append(camera)
		tracked_objects[camera.get_path()] = "camera"
		print("[SceneObjectSync] Registered camera for sync")
	
	# 3. 查找静态目标点（如果需要）
	var stage = main.get_node_or_null("StageDecor/Stage")
	if stage:
		scene_objects.append(stage)
		tracked_objects[stage.get_path()] = "stage"
	
	var ramp = main.get_node_or_null("PhysicsTest/Ramp")
	if ramp:
		scene_objects.append(ramp)
		tracked_objects[ramp.get_path()] = "ramp"

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
