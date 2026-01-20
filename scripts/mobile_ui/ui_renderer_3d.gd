class_name UIRenderer3D
extends Node

# 渲染配置
@export var default_panel_size: Vector2 = Vector2(800, 600)
@export var default_scale: Vector3 = Vector3(0.15, 0.15, 0.15) # 放大三倍 (从0.05到0.15)
@export var texture_filter: bool = true

# SubViewport集合
var viewports: Dictionary = {}
var sprites: Dictionary = {}
var ui_roots: Dictionary = {}

# 面板配置缓存
var panel_configs: Dictionary = {}

# 信号
signal panel_created(panel_id: String, panel: Node3D)
signal panel_updated(panel_id: String, updates: Dictionary)
signal panel_removed(panel_id: String)

# UI组件工厂
var component_factory: Node

func _ready():
	component_factory = load("res://scripts/mobile_ui/ui_component_factory.gd").new()
	add_child(component_factory)

func create_panel(panel_id: String, config: Dictionary) -> Sprite3D:
	print("[UIRenderer3D] Creating panel: ", panel_id)
	
	# 关键修复：处理 size 的类型转换
	var size_data = config.get("size", default_panel_size)
	var panel_size = Vector2(800, 600)
	if size_data is Array and size_data.size() >= 2:
		panel_size = Vector2(size_data[0], size_data[1])
	elif size_data is Vector2:
		panel_size = size_data
	
	print("[UIRenderer3D] Resolved panel size: ", panel_size)

	# 创建SubViewport
	var viewport = SubViewport.new()
	viewport.size = Vector2i(panel_size.x, panel_size.y) # 强制转为 Vector2i
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	# 创建UI根节点
	var ui_root = Control.new()
	ui_root.custom_minimum_size = panel_size
	ui_root.size = panel_size
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 强制一个默认深色背景，并确保它撑满
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # 撑满全屏
	bg.color = Color(config.get("background_color", "#1e293b"))
	ui_root.add_child(bg)
	print("[UIRenderer3D] Added background color: ", bg.color)
	
	viewport.add_child(ui_root)

	# 创建Sprite3D显示
	var sprite = Sprite3D.new()
	sprite.texture = viewport.get_texture()
	sprite.double_sided = true # 双面可见

	# 配置纹理过滤 (Godot 4.x 使用 ViewportTexture 默认设置)
	# ViewportTexture 在 Godot 4 中不直接使用 Texture2D.FLAG_FILTER
	
	sprite.scale = config.get("scale", default_scale)
	sprite.position = config.get("position", Vector3.ZERO)
	sprite.rotation = config.get("rotation", Vector3.ZERO)

	# 设置材质属性
	_configure_sprite_material(sprite, config)

	add_child(sprite)

	# 存储引用
	viewports[panel_id] = viewport
	sprites[panel_id] = sprite
	ui_roots[panel_id] = ui_root
	panel_configs[panel_id] = config

	# 创建UI内容
	_create_panel_content(panel_id, config)

	# 设置碰撞体用于交互检测
	_setup_collision_shape(panel_id, sprite, config)

	panel_created.emit(panel_id, sprite)
	return sprite

func update_panel(panel_id: String, updates: Dictionary):
	if not sprites.has(panel_id):
		return

	print("[UIRenderer3D] Updating panel: ", panel_id)
	var sprite = sprites[panel_id]
	var config = panel_configs[panel_id]

	# 更新位置、旋转、缩放
	if updates.has("position"):
		sprite.position = updates.position
	if updates.has("rotation"):
		sprite.rotation = updates.rotation
	if updates.has("scale"):
		sprite.scale = updates.scale

	# 更新可见性
	if updates.has("visible"):
		sprite.visible = updates.visible

	# 更新材质属性
	if updates.has("material"):
		_update_sprite_material(sprite, updates.material)

	# 更新UI内容
	if updates.has("content") or updates.has("config"):
		var content = updates.get("content", updates.get("config", {}).get("content", {}))
		if not content.is_empty():
			print("[UIRenderer3D] Updating panel content for ", panel_id)
			_update_panel_content(panel_id, content)

	# 更新配置缓存
	for key in updates.keys():
		if key != "content":
			config[key] = updates[key]

	# 强制刷新 Viewport
	if viewports.has(panel_id):
		viewports[panel_id].render_target_update_mode = SubViewport.UPDATE_ONCE
		viewports[panel_id].render_target_update_mode = SubViewport.UPDATE_ALWAYS

	panel_updated.emit(panel_id, updates)

func remove_panel(panel_id: String):
	if sprites.has(panel_id):
		# 清理SubViewport
		if viewports.has(panel_id):
			viewports[panel_id].queue_free()
			viewports.erase(panel_id)

		# 清理UI根节点
		if ui_roots.has(panel_id):
			ui_roots[panel_id].queue_free()
			ui_roots.erase(panel_id)

		# 清理Sprite3D
		sprites[panel_id].queue_free()
		sprites.erase(panel_id)

		# 清理配置
		panel_configs.erase(panel_id)

		panel_removed.emit(panel_id)

func get_panel(panel_id: String) -> Sprite3D:
	return sprites.get(panel_id, null)

func get_all_panels() -> Dictionary:
	return sprites.duplicate()

func _configure_sprite_material(sprite: Sprite3D, config: Dictionary):
	# 创建自定义材质
	var material = StandardMaterial3D.new()

	# 关键修复：必须将 Viewport 纹理赋值给材质的 albedo
	material.albedo_texture = sprite.texture
	
	# 设置材质属性
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # 禁用光照影响
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED # 双面可见
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# 应用材质
	sprite.material_override = material
	print("[UIRenderer3D] Material configured with viewport texture: ", sprite.texture)

func _update_sprite_material(sprite: Sprite3D, material_config: Dictionary):
	if not sprite.material_override:
		return

	var material = sprite.material_override as StandardMaterial3D

	# 更新材质属性
	if material_config.has("opacity"):
		material.albedo_color.a = material_config.opacity

	if material_config.has("emissive"):
		material.emission_enabled = true
		material.emission = material_config.emissive

func _create_panel_content(panel_id: String, config: Dictionary):
	var ui_root = ui_roots[panel_id]
	var content = config.get("content", {})
	print("[UIRenderer3D] Creating panel content for ", panel_id)
	print("[UIRenderer3D] Content: ", content)

	# 清空现有内容 (排除背景节点)
	for child in ui_root.get_children():
		if child.name != "Background":
			child.queue_free()

	# 关键修复：从 content 找 type，找不到则回退到 config.type
	var content_type = content.get("type", config.get("type", "container"))
	print("[UIRenderer3D] Content type detected: ", content_type)
	
	match content_type:
		"form":
			component_factory.create_form(ui_root, content)
		"button":
			component_factory.create_button(ui_root, content)
		"text":
			component_factory.create_text(ui_root, content)
		"list":
			component_factory.create_list(ui_root, content)
		"container":
			component_factory.create_container(ui_root, content)
		_:
			component_factory.create_custom_component(ui_root, content)

func _update_panel_content(panel_id: String, content_updates: Dictionary):
	var ui_root = ui_roots[panel_id]

	# 如果包含 container_type 或 children，说明是一个完整的布局定义，建议重建
	if content_updates.has("type") or content_updates.has("container_type") or content_updates.has("children"):
		# 完全重建内容
		_create_panel_content(panel_id, {"content": content_updates})
	else:
		# 否则尝试增量更新现有组件
		component_factory.update_component(ui_root, content_updates)

func _setup_collision_shape(panel_id: String, sprite: Sprite3D, config: Dictionary):
	# 创建Area3D用于交互检测
	var area = Area3D.new()
	area.name = "InteractionArea"
	sprite.add_child(area)

	# 创建碰撞形状
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()

	# 根据面板大小设置碰撞盒
	var panel_size = config.get("size", default_panel_size)
	var scale = config.get("scale", default_scale)

	# 计算实际3D尺寸
	var box_size = Vector3(
		panel_size.x * scale.x / 100.0,  # 缩放因子调整
		panel_size.y * scale.y / 100.0,
		0.01  # 薄的碰撞盒
	)
	box_shape.size = box_size

	collision_shape.shape = box_shape
	area.add_child(collision_shape)

	# 设置碰撞层
	area.collision_layer = 1 << 1  # 自定义碰撞层
	area.collision_mask = 0  # 不检测其他碰撞

	# 连接交互信号
	area.input_event.connect(_on_area_input_event.bind(panel_id))

func _on_area_input_event(camera: Camera3D, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int, panel_id: String):
	# 将事件转发给交互处理器
	var interaction_handler = get_parent().get_node_or_null("InteractionHandler")
	if interaction_handler:
		interaction_handler.process_input_event(panel_id, event, position)

# 获取面板的世界边界
func get_panel_bounds(panel_id: String) -> AABB:
	if not sprites.has(panel_id):
		return AABB()

	var sprite = sprites[panel_id]
	var config = panel_configs[panel_id]

	var panel_size = config.get("size", default_panel_size)
	var scale = sprite.scale

	# 计算实际边界
	var half_size = Vector3(
		panel_size.x * scale.x / 200.0,  # 除以200是因为默认缩放是0.05，800*0.05/2 = 20
		panel_size.y * scale.y / 200.0,
		0.01
	)

	return AABB(sprite.position - half_size, half_size * 2)

# 射线检测面板
func raycast_panel(screen_pos: Vector2, camera: Camera3D) -> Dictionary:
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000.0

	var space_state = get_viewport().world_3d.direct_space_state

	for panel_id in sprites.keys():
		var sprite = sprites[panel_id]
		var area = sprite.get_node_or_null("InteractionArea")
		if area:
			var query = PhysicsRayQueryParameters3D.create(from, to)
			query.collide_with_areas = true

			var result = space_state.intersect_ray(query)
			if result and result.collider == area:
				# 计算本地坐标
				var local_pos = _calculate_local_position(result.position, sprite, panel_configs[panel_id])
				return {
					"panel_id": panel_id,
					"position": result.position,
					"local_position": local_pos,
					"normal": result.normal
				}

	return {}

func _calculate_local_position(world_pos: Vector3, sprite: Sprite3D, config: Dictionary) -> Vector2:
	# 将世界坐标转换为面板本地坐标
	var panel_size = config.get("size", default_panel_size)

	# 计算面板的本地坐标系
	var local_pos_3d = sprite.to_local(world_pos)

	# 转换为UV坐标 (0-1)
	var uv_x = (local_pos_3d.x + 0.5)  # 假设碰撞盒中心在原点
	var uv_y = (local_pos_3d.y + 0.5)

	# 转换为像素坐标
	var pixel_x = uv_x * panel_size.x
	var pixel_y = uv_y * panel_size.y

	return Vector2(pixel_x, pixel_y)

# 批量更新面板
func batch_update_panels(updates: Dictionary):
	for panel_id in updates.keys():
		var panel_updates = updates[panel_id]
		update_panel(panel_id, panel_updates)

# 获取渲染统计信息
func get_render_stats() -> Dictionary:
	return {
		"panel_count": sprites.size(),
		"viewport_count": viewports.size(),
		"total_memory_usage": _calculate_memory_usage()
	}

func _calculate_memory_usage() -> int:
	# 估算内存使用量
	var total_size = 0

	for viewport in viewports.values():
		var texture_size = viewport.size.x * viewport.size.y * 4  # RGBA
		total_size += texture_size

	return total_size
