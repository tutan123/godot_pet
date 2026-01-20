extends MeshInstance3D

class_name VirtualBrowser3D

## VirtualBrowser3D.gd
## 在3D场景中显示虚拟浏览器的组件
## 支持纹理更新、交互检测和3D变换

signal browser_clicked(position: Vector2)
signal browser_dragged(start_pos: Vector2, end_pos: Vector2, duration: float)
signal browser_texture_updated()

@export var browser_width: int = 1920
@export var browser_height: int = 1080
@export var pixel_density: float = 1.0
@export var scale_factor: float = 0.005  # 3D显示的缩放因子
@export var enable_interaction: bool = true
@export var interaction_layer: int = 1

# 显示配置
@export var window_depth: float = 0.05  # 窗口厚度
@export var border_width: float = 0.01   # 边框宽度
@export var border_color: Color = Color(0.2, 0.2, 0.2, 1.0)

# 材质和纹理
var browser_material: StandardMaterial3D
var browser_texture: ImageTexture
var border_material: StandardMaterial3D
var viewport: SubViewport

# 交互状态
var is_dragging: bool = false
var drag_start_pos: Vector2
var drag_start_time: float
var last_mouse_pos: Vector2

# 性能优化
var texture_update_timer: float = 0.0
var texture_update_interval: float = 0.1  # 每100ms更新一次
var needs_texture_update: bool = false

func _ready() -> void:
    _setup_browser_display()
    _setup_collision()
    _setup_border()

func _setup_browser_display() -> void:
    # 创建视口用于离屏渲染
    viewport = SubViewport.new()
    viewport.size = Vector2i(browser_width, browser_height)
    viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED  # 手动控制更新
    viewport.transparent_bg = true
    add_child(viewport)

    # 创建浏览器材质
    browser_material = StandardMaterial3D.new()
    browser_texture = ImageTexture.new()

    # 创建初始空白纹理
    var initial_image = Image.create(browser_width, browser_height, false, Image.FORMAT_RGBA8)
    initial_image.fill(Color(0.1, 0.1, 0.1, 0.8))  # 半透明灰色背景
    browser_texture = ImageTexture.create_from_image(initial_image)

    browser_material.albedo_texture = browser_texture
    browser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

    # 创建主显示面（正面）
    var plane_mesh = PlaneMesh.new()
    plane_mesh.size = Vector2(browser_width * scale_factor, browser_height * scale_factor)
    plane_mesh.orientation = PlaneMesh.FACE_Z  # 面向Z轴
    mesh = plane_mesh
    material_override = browser_material

func _setup_collision() -> void:
    # 创建碰撞形状用于交互检测
    if enable_interaction:
        var static_body = StaticBody3D.new()
        add_child(static_body)

        var collision_shape = CollisionShape3D.new()
        var box_shape = BoxShape3D.new()
        box_shape.size = Vector3(
            browser_width * scale_factor,
            browser_height * scale_factor,
            window_depth
        )
        collision_shape.shape = box_shape
        static_body.add_child(collision_shape)

        # 设置碰撞层
        static_body.collision_layer = interaction_layer
        static_body.collision_mask = 0  # 不与其他对象碰撞，只用于射线检测

func _setup_border() -> void:
    # 创建边框效果
    border_material = StandardMaterial3D.new()
    border_material.albedo_color = border_color
    border_material.metallic = 0.1
    border_material.roughness = 0.8

    # 上边框
    var top_border = MeshInstance3D.new()
    var top_mesh = BoxMesh.new()
    top_mesh.size = Vector3(browser_width * scale_factor + border_width * 2, border_width, window_depth)
    top_border.mesh = top_mesh
    top_border.material_override = border_material
    top_border.position.y = (browser_height * scale_factor) / 2 + border_width / 2
    add_child(top_border)

    # 下边框
    var bottom_border = MeshInstance3D.new()
    var bottom_mesh = BoxMesh.new()
    bottom_mesh.size = Vector3(browser_width * scale_factor + border_width * 2, border_width, window_depth)
    bottom_border.mesh = bottom_mesh
    bottom_border.material_override = border_material
    bottom_border.position.y = -(browser_height * scale_factor) / 2 - border_width / 2
    add_child(bottom_border)

    # 左边框
    var left_border = MeshInstance3D.new()
    var left_mesh = BoxMesh.new()
    left_mesh.size = Vector3(border_width, browser_height * scale_factor, window_depth)
    left_border.mesh = left_mesh
    left_border.material_override = border_material
    left_border.position.x = -(browser_width * scale_factor) / 2 - border_width / 2
    add_child(left_border)

    # 右边框
    var right_border = MeshInstance3D.new()
    var right_mesh = BoxMesh.new()
    right_mesh.size = Vector3(border_width, browser_height * scale_factor, window_depth)
    right_border.mesh = right_mesh
    right_border.material_override = border_material
    right_border.position.x = (browser_width * scale_factor) / 2 + border_width / 2
    add_child(right_border)

func _process(delta: float) -> void:
    # 控制纹理更新频率
    if needs_texture_update:
        texture_update_timer += delta
        if texture_update_timer >= texture_update_interval:
            texture_update_timer = 0.0
            needs_texture_update = false
            _update_browser_texture()

func update_browser_content(image_data: PackedByteArray, format: String = "png") -> void:
    # 从外部接收浏览器截图数据并更新纹理
    if image_data.is_empty():
        return

    var image = Image.new()

    var load_result = false
    match format.to_lower():
        "png":
            load_result = image.load_png_from_buffer(image_data)
        "jpg", "jpeg":
            load_result = image.load_jpg_from_buffer(image_data)
        "webp":
            load_result = image.load_webp_from_buffer(image_data)

    if load_result == OK:
        # 调整图像大小以适应显示需求
        if image.get_width() != browser_width or image.get_height() != browser_height:
            image.resize(browser_width, browser_height, Image.INTERPOLATE_LANCZOS)

        browser_texture = ImageTexture.create_from_image(image)
        browser_material.albedo_texture = browser_texture

        browser_texture_updated.emit()
    else:
        print("[VirtualBrowser3D] Failed to load image data, format: ", format)

func update_browser_content_from_path(image_path: String) -> void:
    # 从文件路径加载浏览器内容
    if not FileAccess.file_exists(image_path):
        print("[VirtualBrowser3D] Image file not found: ", image_path)
        return

    var image = Image.new()
    var load_result = image.load(image_path)

    if load_result == OK:
        if image.get_width() != browser_width or image.get_height() != browser_height:
            image.resize(browser_width, browser_height, Image.INTERPOLATE_LANCZOS)

        browser_texture = ImageTexture.create_from_image(image)
        browser_material.albedo_texture = browser_texture

        browser_texture_updated.emit()
    else:
        print("[VirtualBrowser3D] Failed to load image from path: ", image_path)

func _update_browser_texture() -> void:
    # 手动触发纹理更新（用于视口渲染模式）
    if viewport:
        viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func get_browser_plane_size() -> Vector2:
    return Vector2(browser_width * scale_factor, browser_height * scale_factor)

func screen_point_to_browser_uv(screen_point: Vector2, camera: Camera3D) -> Vector2:
    # 将屏幕坐标转换为浏览器UV坐标
    var ray_origin = camera.project_ray_origin(screen_point)
    var ray_direction = camera.project_ray_normal(screen_point)

    # 计算射线与浏览器的交点
    var plane_normal = global_transform.basis.z.normalized()
    var plane_point = global_position

    var denominator = plane_normal.dot(ray_direction)
    if abs(denominator) < 0.0001:
        return Vector2(-1, -1)  # 平行于平面

    var t = (plane_point - ray_origin).dot(plane_normal) / denominator
    if t < 0:
        return Vector2(-1, -1)  # 射线方向相反

    var intersection_point = ray_origin + ray_direction * t

    # 转换为本地坐标
    var local_point = to_local(intersection_point)

    # 转换为UV坐标 (0-1范围)
    var half_width = (browser_width * scale_factor) / 2
    var half_height = (browser_height * scale_factor) / 2

    var u = (local_point.x + half_width) / (2 * half_width)
    var v = (local_point.y + half_height) / (2 * half_height)

    # 确保UV在有效范围内
    u = clamp(u, 0.0, 1.0)
    v = clamp(v, 0.0, 1.0)

    return Vector2(u, v)

func browser_uv_to_screen_point(uv: Vector2, camera: Camera3D) -> Vector2:
    # 将浏览器UV坐标转换为屏幕坐标
    var half_width = (browser_width * scale_factor) / 2
    var half_height = (browser_height * scale_factor) / 2

    var local_x = (uv.x - 0.5) * 2 * half_width
    var local_y = (uv.y - 0.5) * 2 * half_height

    var local_point = Vector3(local_x, local_y, 0)
    var world_point = to_global(local_point)

    return camera.unproject_position(world_point)

func set_browser_opacity(opacity: float) -> void:
    # 设置浏览器透明度
    browser_material.albedo_color.a = clamp(opacity, 0.0, 1.0)

func set_browser_scale(new_scale: float) -> void:
    # 设置浏览器显示缩放
    scale_factor = new_scale
    _update_browser_size()

func _update_browser_size() -> void:
    if mesh and mesh is PlaneMesh:
        var plane_mesh = mesh as PlaneMesh
        plane_mesh.size = Vector2(browser_width * scale_factor, browser_height * scale_factor)

func highlight_browser_area(uv_rect: Rect2, color: Color = Color.YELLOW, duration: float = 1.0) -> void:
    # 高亮显示浏览器特定区域（用于交互反馈）
    # 这里可以扩展为在浏览器上绘制高亮覆盖层
    pass

func take_browser_screenshot() -> Image:
    # 获取当前浏览器内容的截图
    if browser_texture:
        return browser_texture.get_image()
    return null

func enable_browser_interaction(enabled: bool) -> void:
    enable_interaction = enabled
    # 更新碰撞检测状态
    for child in get_children():
        if child is StaticBody3D:
            child.set_collision_layer_value(interaction_layer, enabled)

# 交互处理方法（由外部InputManager调用）
func handle_mouse_click(position: Vector2) -> void:
    if not enable_interaction:
        return

    browser_clicked.emit(position)

func handle_mouse_drag_start(position: Vector2) -> void:
    if not enable_interaction:
        return

    is_dragging = true
    drag_start_pos = position
    drag_start_time = Time.get_time()

func handle_mouse_drag_end(end_position: Vector2) -> void:
    if not enable_interaction or not is_dragging:
        return

    is_dragging = false
    var duration = Time.get_time() - drag_start_time
    browser_dragged.emit(drag_start_pos, end_position, duration)

func handle_mouse_move(position: Vector2) -> void:
    if not enable_interaction:
        return

    last_mouse_pos = position

    # 可以在这里添加鼠标悬停效果
    if is_dragging:
        # 处理拖拽过程中的视觉反馈
        pass