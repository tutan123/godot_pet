extends Node

class_name BrowserManager

## BrowserManager.gd
## 虚拟浏览器系统的核心管理器
## 协调进程管理、3D显示、WebSocket通信和用户交互

signal browser_ready()
signal browser_mode_changed(mode: BrowserMode)
signal browser_interaction_detected(event_type: String, data: Dictionary)

enum BrowserMode {
    HIDDEN,        # 隐藏
    WINDOW_3D,     # 3D窗口模式
    OVERLAY_2D,    # 2D覆盖层模式
    FULLSCREEN     # 全屏模式
}

# 浏览器配置
@export var default_url: String = "http://localhost:3000"
@export var auto_start_browser: bool = true
@export var default_mode: BrowserMode = BrowserMode.WINDOW_3D
@export var enable_screenshots: bool = true
@export var screenshot_interval: float = 0.5  # 截图间隔（秒）

# 组件引用
var process_manager: BrowserProcessManager
var virtual_browser: VirtualBrowser3D
var websocket_client: Node  # 引用现有的WebSocketClient

# 状态管理
var current_mode: BrowserMode = BrowserMode.HIDDEN
var is_browser_ready: bool = false
var screenshot_timer: float = 0.0
var pending_browser_events: Array = []

# 交互状态
var interaction_camera: Camera3D
var is_interacting_with_browser: bool = false

func _ready() -> void:
    _initialize_components()
    _connect_signals()
    _setup_initial_state()

func _initialize_components() -> void:
    # 创建并添加浏览器进程管理器
    process_manager = BrowserProcessManager.new()
    add_child(process_manager)

    # 创建并添加虚拟浏览器3D组件
    virtual_browser = VirtualBrowser3D.new()
    add_child(virtual_browser)

    # 获取现有的WebSocket客户端
    websocket_client = get_node_or_null("../WebSocketClient")
    if not websocket_client:
        print("[BrowserManager] Warning: WebSocketClient not found")

func _connect_signals() -> void:
    # 连接进程管理器信号
    process_manager.browser_started.connect(_on_browser_started)
    process_manager.browser_stopped.connect(_on_browser_stopped)
    process_manager.browser_error.connect(_on_browser_error)
    process_manager.browser_health_check.connect(_on_browser_health_check)

    # 连接虚拟浏览器信号
    virtual_browser.browser_clicked.connect(_on_browser_clicked)
    virtual_browser.browser_dragged.connect(_on_browser_dragged)
    virtual_browser.browser_texture_updated.connect(_on_browser_texture_updated)

    # 连接WebSocket信号
    if websocket_client and websocket_client.has_signal("message_received"):
        websocket_client.message_received.connect(_on_websocket_message)

func _setup_initial_state() -> void:
    current_mode = BrowserMode.HIDDEN
    virtual_browser.hide()

    if auto_start_browser:
        start_browser_system()

func _process(delta: float) -> void:
    if enable_screenshots and is_browser_ready:
        screenshot_timer += delta
        if screenshot_timer >= screenshot_interval:
            screenshot_timer = 0.0
            _request_browser_screenshot()

func start_browser_system() -> bool:
    print("[BrowserManager] Starting browser system...")

    if process_manager.start_browser(default_url):
        print("[BrowserManager] Browser process started, waiting for ready signal...")
        return true
    else:
        print("[BrowserManager] Failed to start browser system")
        return false

func stop_browser_system() -> void:
    print("[BrowserManager] Stopping browser system...")
    process_manager.stop_browser()
    set_browser_mode(BrowserMode.HIDDEN)

func set_browser_mode(mode: BrowserMode) -> void:
    if mode == current_mode:
        return

    var previous_mode = current_mode
    current_mode = mode

    match mode:
        BrowserMode.HIDDEN:
            virtual_browser.hide()
        BrowserMode.WINDOW_3D:
            virtual_browser.show()
            virtual_browser.enable_browser_interaction(true)
        BrowserMode.OVERLAY_2D:
            virtual_browser.show()
            virtual_browser.enable_browser_interaction(true)
            # 这里可以添加2D覆盖层逻辑
        BrowserMode.FULLSCREEN:
            virtual_browser.show()
            virtual_browser.enable_browser_interaction(true)
            # 这里可以添加全屏逻辑

    browser_mode_changed.emit(mode)
    print("[BrowserManager] Browser mode changed: ", BrowserMode.keys()[previous_mode], " -> ", BrowserMode.keys()[mode])

func navigate_to_url(url: String) -> void:
    if not is_browser_ready:
        print("[BrowserManager] Browser not ready, queuing navigation")
        return

    send_browser_command("navigate", {"url": url})

func send_browser_command(command: String, data: Dictionary = {}) -> void:
    if not websocket_client:
        print("[BrowserManager] WebSocket client not available")
        return

    var message = {
        "type": "browser_control",
        "timestamp": Time.get_unix_time_from_system(),
        "data": {
            "command": command,
            "params": data
        }
    }

    websocket_client.send_json(message)

func inject_javascript(code: String) -> void:
    send_browser_command("execute_script", {"code": code})

func simulate_mouse_event(event_type: String, x: int, y: int, button: String = "left") -> void:
    var event_data = {
        "type": event_type,
        "x": x,
        "y": y,
        "button": button
    }
    send_browser_command("mouse_event", event_data)

func simulate_keyboard_event(key: String, event_type: String = "keydown") -> void:
    var event_data = {
        "type": event_type,
        "key": key
    }
    send_browser_command("keyboard_event", event_data)

func _request_browser_screenshot() -> void:
    if not enable_screenshots:
        return

    send_browser_command("take_screenshot", {
        "format": "png",
        "quality": 80
    })

func _on_browser_started() -> void:
    print("[BrowserManager] Browser process started successfully")
    # 等待一小段时间让浏览器完全加载
    await get_tree().create_timer(3.0).timeout
    _initialize_browser_connection()

func _initialize_browser_connection() -> void:
    # 发送浏览器就绪信号到服务端
    if websocket_client:
        var ready_message = {
            "type": "browser_ready",
            "timestamp": Time.get_unix_time_from_system(),
            "data": {
                "url": default_url,
                "capabilities": ["screenshot", "interaction", "javascript"]
            }
        }
        websocket_client.send_json(ready_message)

    # 设置默认模式
    set_browser_mode(default_mode)
    is_browser_ready = true
    browser_ready.emit()

func _on_browser_stopped() -> void:
    print("[BrowserManager] Browser stopped")
    is_browser_ready = false
    set_browser_mode(BrowserMode.HIDDEN)

func _on_browser_error(error: String) -> void:
    print("[BrowserManager] Browser error: ", error)
    is_browser_ready = false

func _on_browser_health_check(healthy: bool) -> void:
    if not healthy and is_browser_ready:
        print("[BrowserManager] Browser health check failed")
        is_browser_ready = false
        # 可以在这里触发重启逻辑

func _on_browser_texture_updated() -> void:
    # 浏览器纹理更新回调
    pass

func _on_websocket_message(type: String, data: Dictionary) -> void:
    match type:
        "browser_event":
            _handle_browser_event(data)
        "browser_screenshot":
            _handle_browser_screenshot(data)
        "browser_response":
            _handle_browser_response(data)

func _handle_browser_event(event_data: Dictionary) -> void:
    # 处理浏览器界面事件
    var event_type = event_data.get("event_type", "")
    browser_interaction_detected.emit(event_type, event_data)

    match event_type:
        "click":
            _handle_click_event(event_data)
        "input":
            _handle_input_event(event_data)
        "navigation":
            _handle_navigation_event(event_data)
        "load":
            _handle_load_event(event_data)

func _handle_browser_screenshot(screenshot_data: Dictionary) -> void:
    # 处理浏览器截图数据
    var image_data = screenshot_data.get("image_data", "")
    var format = screenshot_data.get("format", "png")

    if image_data != "":
        var decoded_data = Marshalls.base64_to_raw(image_data)
        virtual_browser.update_browser_content(decoded_data, format)

func _handle_browser_response(response_data: Dictionary) -> void:
    # 处理浏览器命令响应
    var command_id = response_data.get("command_id", "")
    var success = response_data.get("success", false)
    var result = response_data.get("result", {})

    print("[BrowserManager] Browser command response: ", command_id, " success: ", success)

func _handle_click_event(event_data: Dictionary) -> void:
    var element_id = event_data.get("element_id", "")
    var element_tag = event_data.get("element_tag", "")
    var element_text = event_data.get("element_text", "")

    print("[BrowserManager] Browser click: ", element_tag, " id: ", element_id, " text: ", element_text)

    # 这里可以添加点击处理逻辑，比如触发游戏事件

func _handle_input_event(event_data: Dictionary) -> void:
    var input_value = event_data.get("value", "")
    var input_type = event_data.get("input_type", "")

    print("[BrowserManager] Browser input: ", input_type, " value: ", input_value)

func _handle_navigation_event(event_data: Dictionary) -> void:
    var url = event_data.get("url", "")
    print("[BrowserManager] Browser navigation: ", url)

func _handle_load_event(event_data: Dictionary) -> void:
    var url = event_data.get("url", "")
    print("[BrowserManager] Browser page loaded: ", url)

# 公共接口方法
func get_browser_position() -> Vector3:
    return virtual_browser.global_position if virtual_browser else Vector3.ZERO

func set_browser_position(position: Vector3) -> void:
    if virtual_browser:
        virtual_browser.global_position = position

func get_browser_rotation() -> Vector3:
    return virtual_browser.rotation if virtual_browser else Vector3.ZERO

func set_browser_rotation(rotation: Vector3) -> void:
    if virtual_browser:
        virtual_browser.rotation = rotation

func get_browser_scale() -> Vector3:
    return virtual_browser.scale if virtual_browser else Vector3.ONE

func set_browser_scale(scale: Vector3) -> void:
    if virtual_browser:
        virtual_browser.scale = scale

func highlight_browser_element(selector: String, color: Color = Color.YELLOW, duration: float = 2.0) -> void:
    # 高亮显示浏览器中的特定元素
    inject_javascript("""
        var element = document.querySelector('%s');
        if (element) {
            var originalStyle = element.style.cssText;
            element.style.outline = '3px solid %s';
            element.style.outlineOffset = '2px';
            setTimeout(function() {
                element.style.cssText = originalStyle;
            }, %d);
        }
    """ % [selector, color.to_html(), int(duration * 1000)])

func scroll_browser_to_element(selector: String) -> void:
    # 滚动浏览器到指定元素
    inject_javascript("""
        var element = document.querySelector('%s');
        if (element) {
            element.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
    """ % selector)

func get_browser_info() -> Dictionary:
    return {
        "is_ready": is_browser_ready,
        "current_mode": current_mode,
        "url": default_url,
        "position": get_browser_position(),
        "size": virtual_browser.get_browser_plane_size() if virtual_browser else Vector2.ZERO
    }

# 输入处理接口（由外部InputManager调用）
func handle_input_event(event: InputEvent) -> bool:
    if not is_browser_ready or current_mode == BrowserMode.HIDDEN:
        return false

    # 处理鼠标事件
    if event is InputEventMouseButton:
        return _handle_mouse_button_event(event)
    elif event is InputEventMouseMotion:
        return _handle_mouse_motion_event(event)
    elif event is InputEventKey:
        return _handle_key_event(event)

    return false

func _handle_mouse_button_event(event: InputEventMouseButton) -> bool:
    if not interaction_camera:
        return false

    var browser_uv = virtual_browser.screen_point_to_browser_uv(event.position, interaction_camera)

    if browser_uv.x >= 0 and browser_uv.x <= 1 and browser_uv.y >= 0 and browser_uv.y <= 1:
        # 鼠标在浏览器区域内
        var button_name = "left"
        match event.button_index:
            MOUSE_BUTTON_LEFT:
                button_name = "left"
            MOUSE_BUTTON_RIGHT:
                button_name = "right"
            MOUSE_BUTTON_MIDDLE:
                button_name = "middle"

        if event.pressed:
            simulate_mouse_event("mousedown", int(browser_uv.x * browser_width), int(browser_uv.y * browser_height), button_name)
        else:
            simulate_mouse_event("mouseup", int(browser_uv.x * browser_width), int(browser_uv.y * browser_height), button_name)

            if event.button_index == MOUSE_BUTTON_LEFT:
                virtual_browser.handle_mouse_click(browser_uv)

        return true

    return false

func _handle_mouse_motion_event(event: InputEventMouseMotion) -> bool:
    if not interaction_camera:
        return false

    var browser_uv = virtual_browser.screen_point_to_browser_uv(event.position, interaction_camera)

    if browser_uv.x >= 0 and browser_uv.x <= 1 and browser_uv.y >= 0 and browser_uv.y <= 1:
        # 鼠标在浏览器区域内
        simulate_mouse_event("mousemove", int(browser_uv.x * browser_width), int(browser_uv.y * browser_height))
        return true

    return false

func _handle_key_event(event: InputEventKey) -> bool:
    if not event.pressed:
        return false

    var key_name = ""
    match event.keycode:
        KEY_ENTER:
            key_name = "Enter"
        KEY_BACKSPACE:
            key_name = "Backspace"
        KEY_TAB:
            key_name = "Tab"
        KEY_ESCAPE:
            key_name = "Escape"
        KEY_SPACE:
            key_name = " "
        _:
            key_name = char(event.unicode)

    if key_name != "":
        simulate_keyboard_event(key_name, "keydown")
        return true

    return false

func set_interaction_camera(camera: Camera3D) -> void:
    interaction_camera = camera