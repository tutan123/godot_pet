extends Node

class_name BrowserProcessManager

## BrowserProcessManager.gd
## 管理浏览器进程的启动、监控和通信
## 支持在Godot中集成外部浏览器作为虚拟浏览器界面

signal browser_started()
signal browser_stopped()
signal browser_error(error: String)
signal browser_health_check(healthy: bool)

@export var browser_path: String = "chrome"
@export var browser_args: Array[String] = ["--app=http://localhost:3000", "--disable-web-security", "--disable-background-timer-throttling"]
@export var browser_port: int = 3000
@export var health_check_interval: float = 5.0
@export var auto_restart: bool = true

# 进程管理
var browser_process_id: int = -1
var is_browser_running: bool = false
var health_check_timer: float = 0.0
var restart_attempts: int = 0
var max_restart_attempts: int = 3

# HTTP服务器用于健康检查
var health_check_server: TCPServer
var health_check_thread: Thread
var server_running: bool = false

func _ready() -> void:
    _initialize_browser_config()
    _start_health_check_server()

func _initialize_browser_config() -> void:
    # 根据操作系统自动配置浏览器路径
    match OS.get_name():
        "Windows":
            if browser_path == "chrome":
                browser_path = _find_chrome_windows()
        "macOS":
            if browser_path == "chrome":
                browser_path = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        "Linux":
            if browser_path == "chrome":
                browser_path = "/usr/bin/google-chrome"

    # 添加调试端口参数
    var debug_args = ["--remote-debugging-port=" + str(browser_port)]
    browser_args = debug_args + browser_args

func _find_chrome_windows() -> String:
    # Windows上常见的Chrome安装路径
    var possible_paths = [
        "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
        "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
        "C:\\Users\\" + OS.get_environment("USERNAME") + "\\AppData\\Local\\Google\\Chrome\\Application\\chrome.exe"
    ]

    for path in possible_paths:
        if FileAccess.file_exists(path):
            return path

    return "chrome"  # 回退到PATH中的chrome

func start_browser(url: String = "") -> bool:
    if is_browser_running:
        print("[BrowserManager] Browser is already running")
        return true

    if url != "":
        # 更新URL参数
        var app_found = false
        for i in range(browser_args.size()):
            if browser_args[i].begins_with("--app="):
                browser_args[i] = "--app=" + url
                app_found = true
                break

        if not app_found:
            browser_args.append("--app=" + url)

    print("[BrowserManager] Starting browser with path: ", browser_path)
    print("[BrowserManager] Browser args: ", browser_args)

    # 启动浏览器进程
    var output = []
    var exit_code = OS.execute(browser_path, browser_args, output, false, false)

    if exit_code == 0 or exit_code == -1:  # -1表示异步执行成功
        browser_process_id = 0  # 在Godot中我们无法获取真实的进程ID
        is_browser_running = true
        restart_attempts = 0
        print("[BrowserManager] Browser started successfully")
        browser_started.emit()

        # 等待浏览器完全启动
        await get_tree().create_timer(2.0).timeout
        _start_health_monitoring()

        return true
    else:
        var error_msg = "Failed to start browser (exit code: " + str(exit_code) + ")"
        if output.size() > 0:
            error_msg += "\nOutput: " + str(output)
        print("[BrowserManager] ", error_msg)
        browser_error.emit(error_msg)
        return false

func stop_browser() -> void:
    if not is_browser_running:
        return

    print("[BrowserManager] Stopping browser...")

    # 在Windows上尝试优雅关闭
    if OS.get_name() == "Windows":
        OS.execute("taskkill", ["/F", "/IM", "chrome.exe"], [], false)

    # 也可以尝试通过WebSocket发送关闭命令
    # 这里可以扩展为通过DevTools协议关闭浏览器

    is_browser_running = false
    browser_process_id = -1
    browser_stopped.emit()

func _process(delta: float) -> void:
    if not is_browser_running:
        return

    # 健康检查
    health_check_timer += delta
    if health_check_timer >= health_check_interval:
        health_check_timer = 0.0
        _perform_health_check()

func _perform_health_check() -> void:
    # 通过HTTP请求检查浏览器是否响应
    var http_request = HTTPRequest.new()
    add_child(http_request)

    http_request.request_completed.connect(_on_health_check_response)
    var error = http_request.request("http://localhost:" + str(browser_port) + "/json/version")

    if error != OK:
        _on_health_check_failed()

func _on_health_check_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    if response_code == 200:
        browser_health_check.emit(true)
    else:
        _on_health_check_failed()

func _on_health_check_failed() -> void:
    print("[BrowserManager] Health check failed")
    browser_health_check.emit(false)

    if auto_restart and restart_attempts < max_restart_attempts:
        restart_attempts += 1
        print("[BrowserManager] Attempting to restart browser (attempt " + str(restart_attempts) + ")")
        stop_browser()
        await get_tree().create_timer(2.0).timeout
        start_browser()

func _start_health_monitoring() -> void:
    health_check_timer = 0.0
    set_process(true)

func _start_health_check_server() -> void:
    # 创建简单的HTTP服务器用于浏览器健康检查
    health_check_server = TCPServer.new()

    if health_check_server.listen(0, "127.0.0.1") == OK:
        server_running = true
        health_check_thread = Thread.new()
        health_check_thread.start(_health_check_server_thread)
        print("[BrowserManager] Health check server started on port ", health_check_server.get_local_port())
    else:
        print("[BrowserManager] Failed to start health check server")

func _health_check_server_thread() -> void:
    while server_running:
        if health_check_server.is_connection_available():
            var client = health_check_server.take_connection()
            if client:
                # 简单的HTTP响应
                var response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\": \"healthy\"}"
                client.put_data(response.to_utf8_buffer())
                client.disconnect_from_host()
        OS.delay_msec(100)

func is_browser_healthy() -> bool:
    # 简单的进程检查
    return is_browser_running

func get_browser_url() -> String:
    return "http://localhost:" + str(browser_port)

func send_browser_command(command: String, params: Dictionary = {}) -> void:
    # 通过DevTools协议发送命令到浏览器
    # 这里可以扩展为更完整的Chrome DevTools协议实现
    if not is_browser_running:
        return

    var http_request = HTTPRequest.new()
    add_child(http_request)

    var command_data = {
        "id": 1,
        "method": command,
        "params": params
    }

    http_request.request_completed.connect(_on_command_response)
    var json_data = JSON.stringify(command_data).to_utf8_buffer()
    var headers = ["Content-Type: application/json"]
    http_request.request("http://localhost:" + str(browser_port) + "/json", headers, HTTPClient.METHOD_POST, json_data)

func _on_command_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    if response_code == 200:
        print("[BrowserManager] Browser command executed successfully")
    else:
        print("[BrowserManager] Browser command failed: ", response_code)

func _exit_tree() -> void:
    server_running = false
    if health_check_thread and health_check_thread.is_alive():
        health_check_thread.wait_to_finish()

    stop_browser()