extends Node

class_name BrowserInputManager

## BrowserInputManager.gd
## 处理虚拟浏览器的输入交互
## 支持鼠标、键盘事件到浏览器的映射

signal browser_mouse_click(position: Vector2, button: String)
signal browser_mouse_drag(start_pos: Vector2, end_pos: Vector2, duration: float)
signal browser_key_press(key: String, event_type: String)
signal browser_scroll(delta: Vector2)

@export var enable_browser_input: bool = true
@export var interaction_distance: float = 10.0  # 最大交互距离
@export var drag_threshold: float = 10.0  # 拖拽判定阈值

# 浏览器管理器引用
var browser_manager: BrowserManager
var camera: Camera3D

# 输入状态
var is_interacting_with_browser: bool = false
var mouse_over_browser: bool = false
var drag_start_position: Vector2
var drag_start_time: float
var is_dragging: bool = false

# 交互配置
var mouse_sensitivity: float = 1.0
var scroll_sensitivity: float = 1.0

func _ready() -> void:
    _find_browser_manager()
    _find_camera()

func _find_browser_manager() -> void:
    # 查找BrowserManager节点
    browser_manager = get_node_or_null("../BrowserManager")
    if not browser_manager:
        browser_manager = get_node_or_null("/root/Main/BrowserManager")
    if not browser_manager:
        push_warning("BrowserInputManager: BrowserManager not found")

func _find_camera() -> void:
    # 查找相机节点
    camera = get_viewport().get_camera_3d()
    if not camera:
        # 尝试查找常见的相机节点
        camera = get_node_or_null("../Camera3D")
        if not camera:
            camera = get_node_or_null("/root/Main/Camera3D")

func _input(event: InputEvent) -> void:
    if not enable_browser_input or not browser_manager or not camera:
        return

    # 检查是否与浏览器交互
    var browser_interaction = _check_browser_interaction(event)
    if not browser_interaction:
        return

    # 处理不同类型的输入事件
    if event is InputEventMouseButton:
        _handle_mouse_button(event, browser_interaction)
    elif event is InputEventMouseMotion:
        _handle_mouse_motion(event, browser_interaction)
    elif event is InputEventKey:
        _handle_key_event(event)

func _check_browser_interaction(event: InputEvent) -> Dictionary:
    # 检查鼠标事件是否与浏览器交互
    if not (event is InputEventMouseButton or event is InputEventMouseMotion):
        return {}

    if not camera:
        return {}

    # 获取虚拟浏览器
    var virtual_browser = browser_manager.virtual_browser if browser_manager else null
    if not virtual_browser:
        return {}

    # 计算鼠标射线与浏览器的交点
    var mouse_pos = event.position if event is InputEventMouse else get_viewport().get_mouse_position()
    var ray_origin = camera.project_ray_origin(mouse_pos)
    var ray_direction = camera.project_ray_normal(mouse_pos)

    # 计算射线与浏览器的距离
    var browser_pos = virtual_browser.global_position
    var distance_to_browser = ray_origin.distance_to(browser_pos)

    if distance_to_browser > interaction_distance:
        mouse_over_browser = false
        return {}

    # 检查射线是否与浏览器平面相交
    var browser_uv = virtual_browser.screen_point_to_browser_uv(mouse_pos, camera)

    if browser_uv.x >= 0 and browser_uv.x <= 1 and browser_uv.y >= 0 and browser_uv.y <= 1:
        mouse_over_browser = true
        return {
            "uv": browser_uv,
            "world_pos": browser_pos,
            "distance": distance_to_browser,
            "mouse_pos": mouse_pos
        }
    else:
        mouse_over_browser = false
        return {}

func _handle_mouse_button(event: InputEventMouseButton, interaction: Dictionary) -> void:
    if not interaction:
        return

    var button_name = _get_mouse_button_name(event.button_index)

    if event.pressed:
        # 鼠标按下
        if event.button_index == MOUSE_BUTTON_LEFT:
            drag_start_position = interaction.uv
            drag_start_time = Time.get_time()
            is_dragging = false
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
            browser_scroll.emit(Vector2(0, scroll_sensitivity))
            return
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            browser_scroll.emit(Vector2(0, -scroll_sensitivity))
            return

        # 发送鼠标按下事件到浏览器
        browser_manager.simulate_mouse_event("mousedown", int(interaction.uv.x * 1920), int(interaction.uv.y * 1080), button_name)

    else:
        # 鼠标释放
        if event.button_index == MOUSE_BUTTON_LEFT:
            var drag_distance = interaction.uv.distance_to(drag_start_position)
            var drag_duration = Time.get_time() - drag_start_time

            if drag_distance > drag_threshold and drag_duration > 0.1:
                # 认为是拖拽操作
                browser_mouse_drag.emit(drag_start_position, interaction.uv, drag_duration)
                browser_manager.simulate_mouse_event("drag", int(interaction.uv.x * 1920), int(interaction.uv.y * 1080))
            else:
                # 认为是点击操作
                browser_mouse_click.emit(interaction.uv, button_name)
                browser_manager.simulate_mouse_event("click", int(interaction.uv.x * 1920), int(interaction.uv.y * 1080), button_name)

        # 发送鼠标释放事件到浏览器
        browser_manager.simulate_mouse_event("mouseup", int(interaction.uv.x * 1920), int(interaction.uv.y * 1080), button_name)

    # 标记事件已处理
    get_viewport().set_input_as_handled()

func _handle_mouse_motion(event: InputEventMouseMotion, interaction: Dictionary) -> void:
    if not interaction:
        return

    # 检查是否开始拖拽
    if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not is_dragging:
        var current_pos = interaction.uv
        var drag_distance = current_pos.distance_to(drag_start_position)

        if drag_distance > drag_threshold:
            is_dragging = true

    # 发送鼠标移动事件到浏览器
    if mouse_over_browser:
        browser_manager.simulate_mouse_event("mousemove", int(interaction.uv.x * 1920), int(interaction.uv.y * 1080))

    # 标记事件已处理
    get_viewport().set_input_as_handled()

func _handle_key_event(event: InputEventKey) -> void:
    if not mouse_over_browser:
        return

    var key_name = _get_key_name(event.keycode)

    if key_name != "":
        var event_type = "keydown" if event.pressed else "keyup"
        browser_key_press.emit(key_name, event_type)
        browser_manager.simulate_keyboard_event(key_name, event_type)

        # 标记事件已处理
        get_viewport().set_input_as_handled()

func _get_mouse_button_name(button_index: int) -> String:
    match button_index:
        MOUSE_BUTTON_LEFT:
            return "left"
        MOUSE_BUTTON_RIGHT:
            return "right"
        MOUSE_BUTTON_MIDDLE:
            return "middle"
        MOUSE_BUTTON_WHEEL_UP:
            return "wheel_up"
        MOUSE_BUTTON_WHEEL_DOWN:
            return "wheel_down"
        _:
            return "unknown"

func _get_key_name(keycode: int) -> String:
    # 基本的键码映射
    match keycode:
        KEY_ENTER:
            return "Enter"
        KEY_BACKSPACE:
            return "Backspace"
        KEY_TAB:
            return "Tab"
        KEY_ESCAPE:
            return "Escape"
        KEY_SPACE:
            return " "
        KEY_UP:
            return "ArrowUp"
        KEY_DOWN:
            return "ArrowDown"
        KEY_LEFT:
            return "ArrowLeft"
        KEY_RIGHT:
            return "ArrowRight"
        _:
            # 对于字母和数字键，直接转换为字符
            if keycode >= KEY_A and keycode <= KEY_Z:
                return char(keycode - KEY_A + 97)  # a-z
            elif keycode >= KEY_0 and keycode <= KEY_9:
                return char(keycode - KEY_0 + 48)  # 0-9
            else:
                return ""

# 公共方法
func set_browser_manager(manager: BrowserManager) -> void:
    browser_manager = manager

func set_camera(cam: Camera3D) -> void:
    camera = cam

func is_mouse_over_browser() -> bool:
    return mouse_over_browser

func get_browser_interaction_info() -> Dictionary:
    return {
        "is_interacting": is_interacting_with_browser,
        "mouse_over_browser": mouse_over_browser,
        "is_dragging": is_dragging,
        "interaction_distance": interaction_distance
    }

func set_mouse_sensitivity(sensitivity: float) -> void:
    mouse_sensitivity = sensitivity

func set_scroll_sensitivity(sensitivity: float) -> void:
    scroll_sensitivity = sensitivity

func enable_input(enabled: bool) -> void:
    enable_browser_input = enabled

# 调试方法
func _process(delta: float) -> void:
    # 调试输出（仅在调试模式下）
    if OS.is_debug_build() and Input.is_key_pressed(KEY_F12):
        var info = get_browser_interaction_info()
        print("[BrowserInput] ", info)