extends Node

## eqs_adapter.gd
## EQS 客户端适配器：轻量级适配器，将服务端查询配置转换为 Godot API 调用

const PetLoggerScript = preload("res://scripts/pet_logger.gd")
@onready var PetLogger = PetLoggerScript.new()

## 信号
signal eqs_result_ready(query_id: String, response: Dictionary)

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

## 从上下文中安全获取位置向量
func _get_pos_from_context(context: Dictionary, key: String, default: Vector3 = Vector3.ZERO) -> Vector3:
	var pos = context.get(key)
	if pos == null:
		return default
	
	if pos is Vector3:
		return pos
	
	if pos is Array and pos.size() >= 3:
		return Vector3(pos[0], pos[1], pos[2])
	
	return default

## 处理来自服务端的查询
## @param query_data: 从WebSocket消息的data字段提取的字典
## 支持两种消息格式：
## 1. 直接格式: {query_id: "...", config: {...}, context: {...}}
## 2. 嵌套格式: {query_id: "...", data: {config: {...}, context: {...}}}
func handle_query(query_data: Dictionary) -> void:
	var query_id = query_data.get("query_id", "")
	
	if query_id.is_empty():
		push_warning("[EQSAdapter] Query ID is empty")
		return

	# 尝试从嵌套格式获取config和context
	var data = query_data.get("data", {})
	var config = data.get("config", {})
	var context = data.get("context", {})
	
	# 如果不是嵌套格式，尝试直接格式
	if config.is_empty():
		config = query_data.get("config", {})
	
	# 如果context在config中（旧版本格式）
	if context.is_empty() and config.has("context"):
		var server_context = config.get("context", {})
		context = server_context
	
	# 如果仍然没有context，构建默认上下文
	if context.is_empty():
		# 从pet_controller获取位置信息（需要通过回调或参数传递）
		# 这里先构建空上下文，实际位置会在execute_query中补充
		context = {}

	if config.is_empty():
		push_warning("[EQSAdapter] Query config is empty. Data: %s" % query_data)
		return

	execute_query(query_id, config, context)

## 执行查询
## @param query_id: 查询ID
## @param config: 查询配置（来自服务端）
## @param context: 查询上下文
func execute_query(query_id: String, config: Dictionary, context: Dictionary) -> void:
	PetLogger.info("EQSAdapter", "=== Starting query %s ===" % query_id)
	PetLogger.info("EQSAdapter", "Config: %s" % str(config))
	PetLogger.info("EQSAdapter", "Context: %s" % str(context))

	# 验证context完整性
	if not context.has("querier_position"):
		print("[EQS] ERROR: Missing querier_position in context!")
	if not context.has("target_position"):
		print("[EQS] ERROR: Missing target_position in context!")
	if not context.has("enemy_positions"):
		print("[EQS] WARNING: Missing enemy_positions in context, using empty array")
		context["enemy_positions"] = []

	# 记录开始时间
	query_start_times[query_id] = Time.get_ticks_msec()

	var generator_type = config.get("generator", {}).get("type", "")
	var generator_params = config.get("generator", {}).get("params", {})
	var tests = config.get("tests", [])
	var options = config.get("options", {})

	PetLogger.info("EQSAdapter", "Generator type: %s, params: %s" % [generator_type, str(generator_params)])
	PetLogger.info("EQSAdapter", "Tests: %s" % str(tests))

	# 1. 生成候选点
	var candidate_points = _generate_points(generator_type, generator_params, context)

	if candidate_points.is_empty():
		print("[EQSAdapter] ERROR: No candidate points generated for query %s" % query_id)
		_send_result(query_id, [], "No candidate points generated")
		return

	print("[EQSAdapter] SUCCESS: Generated %d candidate points for query %s" % [candidate_points.size(), query_id])

	for i in range(min(3, candidate_points.size())):
		print("[EQSAdapter] Candidate %d: %s" % [i, str(candidate_points[i])])
	
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
	print("[EQSAdapter] Query %s completed: %d valid results" % [query_id, results.size()])
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
	print("[EQSAdapter] _generate_circle called with params: %s" % str(params))
	print("[EQSAdapter] Context: %s" % str(context))

	var radius = params.get("radius", 10.0)
	var points_count = params.get("points_count", 16)
	var generate_around = params.get("generate_around", "Querier")
	var target_height = params.get("target_height", null)  # 新增：目标高度（用于舞台等）

	print("[EQSAdapter] radius=%f, points_count=%d, generate_around=%s" % [radius, points_count, generate_around])

	var center: Vector3
	match generate_around:
		"Querier":
			center = _get_pos_from_context(context, "querier_position")
			print("[EQSAdapter] Using querier position as center: %s" % str(center))
		"Target":
			center = _get_pos_from_context(context, "target_position")
			print("[EQSAdapter] Using target position as center: %s" % str(center))
		_:
			center = Vector3.ZERO
			print("[EQSAdapter] Using zero as center")

	# 如果指定了目标高度，使用目标高度；否则使用center的Y坐标
	var y_level = target_height if target_height != null else center.y
	print("[EQSAdapter] Y level: %f" % y_level)

	var points: Array[Vector3] = []
	var angle_step = TAU / points_count

	for i in range(points_count):
		var angle = i * angle_step
		var pos = Vector3(
			center.x + cos(angle) * radius,
			y_level,  # 使用计算出的Y坐标
			center.z + sin(angle) * radius
		)
		points.append(pos)

	print("[EQSAdapter] Generated %d points for circle" % points.size())
	return points

## 网格生成器
func _generate_grid(params: Dictionary, context: Dictionary) -> Array[Vector3]:
	var grid_size = params.get("grid_size", [10, 0, 10])
	var space_between = params.get("space_between", 1.0)
	var generate_around = params.get("generate_around", "Querier")
	
	var center: Vector3
	match generate_around:
		"Querier":
			center = _get_pos_from_context(context, "querier_position")
		"Target":
			center = _get_pos_from_context(context, "target_position")
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
func _generate_on_path(params: Dictionary, _context: Dictionary) -> Array[Vector3]:
	var path_points = params.get("path_points", [])
	var points_per_segment = params.get("points_per_segment", 5)
	
	if path_points.size() < 2:
		return []
	
	var points: Array[Vector3] = []
	
	for i in range(path_points.size() - 1):
		var start_arr = path_points[i]
		var end_arr = path_points[i + 1]
		if start_arr == null or end_arr == null: continue
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
		if actor_pos == null: continue
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
			target_pos = _get_pos_from_context(context, "querier_position")
		"DISTANCE_TO_TARGET":
			target_pos = _get_pos_from_context(context, "target_position")
		"DISTANCE_TO_ENEMIES":
			var enemies = context.get("enemy_positions", [])
			if enemies.is_empty() or enemies[0] == null:
				return 1.0
			var enemy = enemies[0]
			target_pos = Vector3(enemy[0], enemy[1], enemy[2])
		_:
			target_pos = point # 默认指向自己或当前点
	
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
			from_pos = _get_pos_from_context(context, "querier_position")
		"Target":
			from_pos = _get_pos_from_context(context, "target_position")
		"Item":
			from_pos = point
		_:
			from_pos = point
	
	# 确定终点
	match trace_to:
		"Querier":
			to_pos = _get_pos_from_context(context, "querier_position")
		"Target":
			to_pos = _get_pos_from_context(context, "target_position")
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
			to_pos = _get_pos_from_context(context, "target_position")
		"DOT_FROM_TARGET":
			from_pos = _get_pos_from_context(context, "target_position")
			to_pos = point
		"DOT_TO_QUERIER":
			from_pos = point
			to_pos = _get_pos_from_context(context, "querier_position")
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
func _test_overlap(point: Vector3, params: Dictionary, _context: Dictionary) -> float:
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
	var allow_fallback = params.get("allow_fallback", true)  # 新增：是否允许降级策略

	if not navmesh:
		print("[EQS] Pathfinding test skipped: no navigation mesh")
		return _fallback_distance_score(point, context, max_path_length)

	var start_pos = _get_pos_from_context(context, "querier_position")
	var end_pos = point

	# 调试：检查导航网格状态
	var navigation_mesh = navmesh.get_navigation_mesh()
	if not navigation_mesh:
		print("[EQS] Navigation mesh is null, using fallback")
		return _fallback_distance_score(point, context, max_path_length)

	# 调试：检查RID是否有效
	var map_rid = navmesh.get_rid()
	if map_rid == RID():
		print("[EQS] Navigation mesh RID is invalid, using fallback")
		return _fallback_distance_score(point, context, max_path_length)

	print("[EQS] Testing path from %s to %s" % [start_pos, end_pos])

	# 直接使用navmesh RID进行路径查找（参考老版本实现）
	var path = NavigationServer3D.map_get_path(
		map_rid,
		start_pos,
		end_pos,
		true  # 优化路径
	)

	if path.is_empty():
		print("[EQS] No path found from %s to %s" % [start_pos, end_pos])
		if require_path_exists:
			if allow_fallback:
				print("[EQS] Using fallback distance-based scoring")
				return _fallback_distance_score(point, context, max_path_length)
			else:
				return -1.0
		return 0.0

	# 计算路径长度
	var path_length = 0.0
	for i in range(path.size() - 1):
		path_length += path[i].distance_to(path[i + 1])

	print("[EQS] Path found with length: %.2f" % path_length)

	if path_length > max_path_length:
		print("[EQS] Path too long: %.2f > %.2f" % [path_length, max_path_length])
		if allow_fallback:
			print("[EQS] Path too long, using fallback distance scoring")
			return _fallback_distance_score(point, context, max_path_length)
		return -1.0

	# 路径越短分数越高
	var score = 1.0 - (path_length / max_path_length)
	var clamped_score = clamp(score, 0.0, 1.0)

	print("[EQS] Pathfinding score: %.3f" % clamped_score)
	return clamped_score

## 降级策略：基于距离的评分
func _fallback_distance_score(point: Vector3, context: Dictionary, max_path_length: float) -> float:
	var start_pos = _get_pos_from_context(context, "querier_position")
	var distance = start_pos.distance_to(point)

	print("[EQS] Fallback: distance from %s to %s is %.2f" % [start_pos, point, distance])

	# 距离越近分数越高（与路径查找相反，更喜欢近的点）
	var score = 1.0 - (distance / max_path_length)
	var clamped_score = clamp(score, 0.0, 1.0)

	print("[EQS] Fallback distance score: %.3f" % clamped_score)
	return clamped_score

## 重新烘焙导航网格（调试用）
func rebake_navigation_mesh() -> void:
	if not navmesh:
		print("[EQS] No navigation mesh to rebake")
		return

	print("[EQS] Rebaking navigation mesh...")

	if navmesh.has_method("bake_navigation_mesh"):
		navmesh.bake_navigation_mesh()

		# 等待烘焙完成
		await navmesh.get_tree().process_frame

		_verify_navigation_mesh()
	else:
		print("[EQS] bake_navigation_mesh method not available")

## 验证导航网格状态
func _verify_navigation_mesh() -> void:
	if not navmesh:
		print("[EQS] No navigation mesh to verify")
		return

	var navigation_mesh = navmesh.get_navigation_mesh()
	if not navigation_mesh:
		print("[EQS] Navigation mesh resource is null")
		return

	var vertices = navigation_mesh.vertices
	var poly_count = navigation_mesh.get_polygon_count()

	print("[EQS] Navigation mesh verification:")
	print("[EQS]   - Vertices: %d" % vertices.size())
	print("[EQS]   - Polygons: %d" % poly_count)
	print("[EQS]   - RID valid: %s" % (navmesh.get_rid() != RID()))

	if vertices.size() == 0 or poly_count == 0:
		print("[EQS] Warning: Navigation mesh appears to be empty")
	else:
		print("[EQS] Navigation mesh looks good")

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
		"error": error if not error.is_empty() else ""
	}
	
	# 通过信号通知，由pet_controller发送
	eqs_result_ready.emit(query_id, response)

## 测试查询处理功能
func test_query_handling() -> void:
	print("[EQS] Testing query handling...")
	var test_query_data = {
		"query_id": "test_query_001",
		"data": {
			"config": {
				"generator": {
					"type": "Points_Circle",
					"params": {
						"radius": 5.0,
						"points_count": 8,
						"generate_around": "Querier"
					}
				},
				"tests": [{
					"type": "Test_Distance",
					"params": {
						"mode": "DISTANCE_TO_TARGET",
						"scoring_equation": "Linear",
						"min_distance": 1.0,
						"max_distance": 10.0
					}
				}],
				"options": {
					"max_results": 3,
					"min_score": 0.0
				}
			},
			"context": {
				"querier_position": [0.0, 0.0, 0.0],
				"target_position": [3.0, 0.0, 3.0]
			}
		}
	}

	handle_query(test_query_data)
	print("[EQS] Query handling test completed")

## 测试导航网格功能（可在编辑器中调用）
func test_navigation_mesh() -> void:
	print("[EQS] Testing navigation mesh...")

	if not navmesh:
		print("[EQS] ❌ No navigation mesh assigned")
		return

	# 检查导航网格
	if not navmesh.get_navigation_mesh():
		print("[EQS] ❌ No navigation mesh found")
		return
	print("[EQS] ✅ Navigation mesh is available")

	print("[EQS] Navigation mesh is ready, testing paths...")

	# 获取导航地图RID
	var map_rid = NavigationServer3D.region_get_map(navmesh.get_rid())
	print("[EQS] Map RID: %s" % map_rid)

	# 从稍微高一点的位置开始测试（避免在导航网格表面上）
	var start_pos = Vector3(0, 0.1, 0)

	# 测试几个路径（在导航网格范围内）
	var test_points = [
		Vector3(3, 0.1, 0),   # 前方3米
		Vector3(0, 0.1, 3),   # 右侧3米
	]

	for point in test_points:
		print("[EQS] Testing path from %s to %s" % [start_pos, point])

		# 使用正确的NavigationServer3D API
		var path = NavigationServer3D.map_get_path(
			map_rid,
			start_pos,
			point,
			true  # optimize
		)

		if path.is_empty():
			print("[EQS] ❌ No path found")
			# 检查是否可以直接到达（简单距离检查）
			var direct_distance = start_pos.distance_to(point)
			print("[EQS]   Direct distance: %.2f" % direct_distance)
		else:
			var path_length = 0.0
			for i in range(path.size() - 1):
				path_length += path[i].distance_to(path[i + 1])
			print("[EQS] ✅ Path found, length: %.2f, points: %d" % [path_length, path.size()])

	print("[EQS] Navigation mesh test completed")
