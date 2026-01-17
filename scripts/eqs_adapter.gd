extends Node

## eqs_adapter.gd
## EQS 客户端适配器：轻量级适配器，将服务端查询配置转换为 Godot API 调用

class_name EQSAdapter

## 信号
signal eqs_result_ready(query_id: String, results: Array)

## 节点引用
var ws_client: Node
var navmesh: NavigationRegion3D

## 查询计时
var query_start_times: Dictionary = {}  # {query_id: start_time}

## 安全获取 World3D
func _get_world_3d() -> World3D:
	if is_inside_tree():
		return get_tree().root.get_world_3d()
	else:
		# 如果不在场景树中，尝试通过主场景获取
		var main_scene = Engine.get_main_loop().current_scene
		if main_scene:
			return main_scene.get_world_3d()
	return null

## 执行查询
## @param query_id: 查询ID
## @param config: 查询配置（来自服务端）
## @param context: 查询上下文
func execute_query(query_id: String, config: Dictionary, context: Dictionary) -> void:
	# 记录开始时间
	query_start_times[query_id] = Time.get_ticks_msec()
	
	var generator_type = config.get("generator", {}).get("type", "")
	var generator_params = config.get("generator", {}).get("params", {})
	var tests = config.get("tests", [])
	var options = config.get("options", {})
	
	# 1. 生成候选点
	var candidate_points = _generate_points(generator_type, generator_params, context)
	
	if candidate_points.is_empty():
		_send_result(query_id, [], "No candidate points generated")
		return
	
	# 2. 执行测试，评估每个点
	var results: Array[Dictionary] = []
	for point in candidate_points:
		var score = _evaluate_point(point, tests, context)
		if score >= 0:  # 负分表示被过滤
			results.append({
				"position": [point.x, point.y, point.z],
				"score": score,
				"test_scores": {}  # 可以扩展记录每个测试的分数
			})
	
	# 3. 按分数排序
	results.sort_custom(func(a, b): return a.score > b.score)
	
	# 4. 应用选项
	var max_results = options.get("max_results", 5)
	var min_score = options.get("min_score", 0.0)
	
	results = results.filter(func(r): return r.score >= min_score)
	if results.size() > max_results:
		results = results.slice(0, max_results)
	
	# 5. 发送结果
	_send_result(query_id, results)

## 生成候选点
func _generate_points(type: String, params: Dictionary, context: Dictionary) -> Array[Vector3]:
	match type:
		"Points_Circle":
			return _generate_circle(params, context)
		"Points_Grid":
			return _generate_grid(params, context)
		"Points_OnPath":
			return _generate_on_path(params, context)
		"Points_FromActors":
			return _generate_from_actors(params, context)
		_:
			push_warning("[EQSAdapter] Unknown generator type: " + type)
			return []

## 圆形生成器
func _generate_circle(params: Dictionary, context: Dictionary) -> Array[Vector3]:
	var radius = params.get("radius", 10.0)
	var points_count = params.get("points_count", 16)
	var generate_around = params.get("generate_around", "Querier")
	
	var center: Vector3
	match generate_around:
		"Querier":
			var qpos = context.get("querier_position", [0, 0, 0])
			center = Vector3(qpos[0], qpos[1], qpos[2])
		"Target":
			var tpos = context.get("target_position", [0, 0, 0])
			center = Vector3(tpos[0], tpos[1], tpos[2])
		_:
			center = Vector3.ZERO
	
	var points: Array[Vector3] = []
	var angle_step = TAU / points_count
	
	for i in range(points_count):
		var angle = i * angle_step
		var pos = center + Vector3(
			cos(angle) * radius,
			0,
			sin(angle) * radius
		)
		points.append(pos)
	
	return points

## 网格生成器
func _generate_grid(params: Dictionary, context: Dictionary) -> Array[Vector3]:
	var grid_size = params.get("grid_size", [10, 0, 10])
	var space_between = params.get("space_between", 1.0)
	var generate_around = params.get("generate_around", "Querier")
	
	var center: Vector3
	match generate_around:
		"Querier":
			var qpos = context.get("querier_position", [0, 0, 0])
			center = Vector3(qpos[0], qpos[1], qpos[2])
		"Target":
			var tpos = context.get("target_position", [0, 0, 0])
			center = Vector3(tpos[0], tpos[1], tpos[2])
		_:
			center = Vector3.ZERO
	
	var size_x = grid_size[0] if grid_size.size() > 0 else 10.0
	var size_z = grid_size[2] if grid_size.size() > 2 else 10.0
	
	var points: Array[Vector3] = []
	var x_steps = int(size_x / space_between)
	var z_steps = int(size_z / space_between)
	
	for x in range(-x_steps/2, x_steps/2 + 1):
		for z in range(-z_steps/2, z_steps/2 + 1):
			var pos = center + Vector3(
				x * space_between,
				0,
				z * space_between
			)
			points.append(pos)
	
	return points

## 路径生成器
func _generate_on_path(params: Dictionary, context: Dictionary) -> Array[Vector3]:
	var path_points = params.get("path_points", [])
	var points_per_segment = params.get("points_per_segment", 5)
	
	if path_points.size() < 2:
		return []
	
	var points: Array[Vector3] = []
	
	for i in range(path_points.size() - 1):
		var start_arr = path_points[i]
		var end_arr = path_points[i + 1]
		var start = Vector3(start_arr[0], start_arr[1], start_arr[2])
		var end = Vector3(end_arr[0], end_arr[1], end_arr[2])
		
		for j in range(points_per_segment):
			var t = float(j) / float(points_per_segment)
			var pos = start.lerp(end, t)
			points.append(pos)
	
	# 添加最后一个点
	if path_points.size() > 0:
		var last = path_points[-1]
		points.append(Vector3(last[0], last[1], last[2]))
	
	return points

## 从Actor生成
func _generate_from_actors(params: Dictionary, context: Dictionary) -> Array[Vector3]:
	var radius = params.get("radius", 5.0)
	var points_per_actor = params.get("points_per_actor", 8)
	
	# 从上下文获取actor位置
	var actor_positions = context.get("actor_positions", [])
	if actor_positions.is_empty():
		return []
	
	var points: Array[Vector3] = []
	
	for actor_pos in actor_positions:
		var center = Vector3(actor_pos[0], actor_pos[1], actor_pos[2])
		var angle_step = TAU / points_per_actor
		
		for i in range(points_per_actor):
			var angle = i * angle_step
			var pos = center + Vector3(
				cos(angle) * radius,
				0,
				sin(angle) * radius
			)
			points.append(pos)
	
	return points

## 评估点
func _evaluate_point(point: Vector3, tests: Array, context: Dictionary) -> float:
	var total_score = 1.0
	
	for test_config in tests:
		var test_type = test_config.get("type", "")
		var test_params = test_config.get("params", {})
		var score = _run_test(point, test_type, test_params, context)
		
		if score < 0:  # 负分表示过滤掉
			return -1.0
		
		# 累积分数（乘法）
		total_score *= score
	
	return clamp(total_score, 0.0, 1.0)

## 执行测试
func _run_test(point: Vector3, test_type: String, params: Dictionary, context: Dictionary) -> float:
	match test_type:
		"Test_Distance":
			return _test_distance(point, params, context)
		"Test_Trace":
			return _test_trace(point, params, context)
		"Test_Dot":
			return _test_dot(point, params, context)
		"Test_Overlap":
			return _test_overlap(point, params, context)
		"Test_Pathfinding":
			return _test_pathfinding(point, params, context)
		_:
			push_warning("[EQSAdapter] Unknown test type: " + test_type)
			return 1.0

## 距离测试
func _test_distance(point: Vector3, params: Dictionary, context: Dictionary) -> float:
	var mode = params.get("mode", "DISTANCE_TO_TARGET")
	var scoring_equation = params.get("scoring_equation", "Linear")
	var min_distance = params.get("min_distance", 0.0)
	var max_distance = params.get("max_distance", 100.0)
	var desired_distance = params.get("desired_distance", 5.0)
	
	var target_pos: Vector3
	
	match mode:
		"DISTANCE_TO_QUERIER":
			var qpos = context.get("querier_position", [0, 0, 0])
			target_pos = Vector3(qpos[0], qpos[1], qpos[2])
		"DISTANCE_TO_TARGET":
			var tpos = context.get("target_position", [0, 0, 0])
			target_pos = Vector3(tpos[0], tpos[1], tpos[2])
		"DISTANCE_TO_ENEMIES":
			var enemies = context.get("enemy_positions", [])
			if enemies.is_empty():
				return 1.0
			var enemy = enemies[0]
			target_pos = Vector3(enemy[0], enemy[1], enemy[2])
		_:
			return 1.0
	
	var distance = point.distance_to(target_pos)
	
	# 超出范围，过滤掉
	if distance < min_distance or distance > max_distance:
		return -1.0
	
	# 计算分数
	var score: float
	match scoring_equation:
		"Linear":
			# 距离越近分数越高
			score = 1.0 - (distance / max_distance)
		"Inverse":
			# 距离越远分数越高
			score = distance / max_distance
		"Custom":
			# 理想距离模式
			var diff = abs(distance - desired_distance)
			var max_diff = max(max_distance - desired_distance, desired_distance - min_distance)
			score = 1.0 - (diff / max_diff)
		_:
			score = 1.0
	
	return clamp(score, 0.0, 1.0)

## 射线检测测试
func _test_trace(point: Vector3, params: Dictionary, context: Dictionary) -> float:
	var trace_type = params.get("trace_type", "LINE_OF_SIGHT")
	var trace_from = params.get("trace_from", "Querier")
	var trace_to = params.get("trace_to", "Target")
	var require_clear_path = params.get("require_clear_path", true)
	
	var from_pos: Vector3
	var to_pos: Vector3
	
	# 确定起点
	match trace_from:
		"Querier":
			var qpos = context.get("querier_position", [0, 0, 0])
			from_pos = Vector3(qpos[0], qpos[1], qpos[2])
		"Target":
			var tpos = context.get("target_position", [0, 0, 0])
			from_pos = Vector3(tpos[0], tpos[1], tpos[2])
		"Item":
			from_pos = point
		_:
			from_pos = point
	
	# 确定终点
	match trace_to:
		"Querier":
			var qpos = context.get("querier_position", [0, 0, 0])
			to_pos = Vector3(qpos[0], qpos[1], qpos[2])
		"Target":
			var tpos = context.get("target_position", [0, 0, 0])
			to_pos = Vector3(tpos[0], tpos[1], tpos[2])
		"Item":
			to_pos = point
		_:
			to_pos = point
	
	# 安全获取 World3D
	var world_3d = _get_world_3d()
	if not world_3d:
		push_warning("[EQSAdapter] Cannot get World3D, skipping trace test")
		return 1.0  # 默认通过
	
	var space_state = world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = 0xFFFFFFFF
	query.exclude = []  # 可以扩展排除列表
	
	var result = space_state.intersect_ray(query)
	
	match trace_type:
		"LINE_OF_SIGHT":
			# 视线检测
			if require_clear_path and result:
				return -1.0
			return 1.0
		"NAVIGATION":
			# 导航网格检测
			if navmesh:
				var nav_pos = navmesh.get_closest_point(to_pos)
				if nav_pos.distance_to(to_pos) > 1.0:
					return -1.0
			return 1.0
		"COLLISION":
			# 碰撞检测
			if result:
				return -1.0
			return 1.0
	
	return 1.0

## 方向测试
func _test_dot(point: Vector3, params: Dictionary, context: Dictionary) -> float:
	var mode = params.get("mode", "DOT_TO_TARGET")
	var min_dot = params.get("min_dot", 0.0)
	var max_dot = params.get("max_dot", 1.0)
	
	var from_pos: Vector3
	var to_pos: Vector3
	
	match mode:
		"DOT_TO_TARGET":
			from_pos = point
			var tpos = context.get("target_position", [0, 0, 0])
			to_pos = Vector3(tpos[0], tpos[1], tpos[2])
		"DOT_FROM_TARGET":
			var tpos = context.get("target_position", [0, 0, 0])
			from_pos = Vector3(tpos[0], tpos[1], tpos[2])
			to_pos = point
		"DOT_TO_QUERIER":
			from_pos = point
			var qpos = context.get("querier_position", [0, 0, 0])
			to_pos = Vector3(qpos[0], qpos[1], qpos[2])
		_:
			return 1.0
	
	var direction = (to_pos - from_pos).normalized()
	var forward = Vector3.FORWARD  # 或从上下文获取
	
	var dot = direction.dot(forward)
	
	if dot < min_dot or dot > max_dot:
		return -1.0
	
	# 归一化到 0-1
	var score = (dot + 1.0) * 0.5
	return clamp(score, 0.0, 1.0)

## 重叠测试
func _test_overlap(point: Vector3, params: Dictionary, context: Dictionary) -> float:
	var overlap_shape = params.get("overlap_shape", null)
	var require_no_overlap = params.get("require_no_overlap", true)
	
	if not overlap_shape:
		return 1.0
	
	# 安全获取 World3D
	var world_3d = _get_world_3d()
	if not world_3d:
		push_warning("[EQSAdapter] Cannot get World3D, skipping overlap test")
		return 1.0  # 默认通过
	
	var space_state = world_3d.direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = overlap_shape
	query.transform.origin = point
	query.collision_mask = 0xFFFFFFFF
	query.exclude = []
	
	var results = space_state.intersect_shape(query)
	
	if require_no_overlap:
		if results.size() > 0:
			return -1.0
		return 1.0
	else:
		return min(float(results.size()) / 10.0, 1.0)

## 路径查找测试
func _test_pathfinding(point: Vector3, params: Dictionary, context: Dictionary) -> float:
	var max_path_length = params.get("max_path_length", 100.0)
	var require_path_exists = params.get("require_path_exists", true)
	
	if not navmesh:
		return 1.0  # 没有导航网格，跳过测试
	
	var qpos = context.get("querier_position", [0, 0, 0])
	var start_pos = Vector3(qpos[0], qpos[1], qpos[2])
	var end_pos = point
	
	# 使用 NavigationServer3D
	var path = NavigationServer3D.map_get_path(
		navmesh.get_rid(),
		start_pos,
		end_pos,
		true  # 优化路径
	)
	
	if path.is_empty():
		if require_path_exists:
			return -1.0
		return 0.0
	
	# 计算路径长度
	var path_length = 0.0
	for i in range(path.size() - 1):
		path_length += path[i].distance_to(path[i + 1])
	
	if path_length > max_path_length:
		return -1.0
	
	# 路径越短分数越高
	var score = 1.0 - (path_length / max_path_length)
	return clamp(score, 0.0, 1.0)

## 发送结果
func _send_result(query_id: String, results: Array, error: String = "") -> void:
	var start_time = query_start_times.get(query_id, Time.get_ticks_msec())
	var execution_time = Time.get_ticks_msec() - start_time
	query_start_times.erase(query_id)
	
	var response = {
		"query_id": query_id,
		"status": "success" if error.is_empty() else "error",
		"results": results,
		"execution_time_ms": execution_time,
		"error": error if not error.is_empty() else null
	}
	
	# 通过信号通知，由pet_controller发送
	eqs_result_ready.emit(query_id, response)
