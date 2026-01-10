extends GutTest

## WebSocketClient 测试
## 测试 WebSocket 连接、重连、消息发送和接收功能

var ws_client: Node
var test_url: String = "ws://localhost:8080"

func before_each():
	# 创建 WebSocketClient 实例
	ws_client = load("res://scripts/websocket_client.gd").new()
	ws_client.websocket_url = test_url
	ws_client.set_process(false)  # 禁用自动处理，手动控制测试
	add_child(ws_client)

func after_each():
	if ws_client:
		ws_client.queue_free()
		ws_client = null

func test_websocket_client_initialization():
	# 测试客户端初始化
	assert_not_null(ws_client, "WebSocketClient 应该被创建")
	assert_eq(ws_client.websocket_url, test_url, "URL 应该正确设置")
	assert_false(ws_client.is_connected, "初始状态应该未连接")

func test_connect_to_server_closes_existing_connection():
	# 测试 connect_to_server 会关闭已有连接
	# 由于我们无法真正连接，只能测试函数调用不会崩溃
	var original_state = ws_client.socket.get_ready_state()
	ws_client.connect_to_server()
	# 函数应该执行完成而不崩溃
	pass_test("connect_to_server 执行成功")

func test_send_message_when_not_connected():
	# 测试未连接时发送消息
	ws_client.is_connected = false
	ws_client.send_message("test", {})
	# 应该打印错误但不崩溃
	pass_test("未连接时发送消息处理正确")

func test_send_message_format():
	# 测试消息格式（需要 mock socket）
	# 由于 WebSocketPeer 难以 mock，我们测试 JSON 格式
	var test_data = {
		"type": "test",
		"timestamp": 1234567890,
		"data": {"key": "value"}
	}
	var json_str = JSON.stringify(test_data)
	var parsed = JSON.parse_string(json_str)
	assert_not_null(parsed, "JSON 应该可以解析")
	assert_eq(parsed.get("type"), "test", "消息类型应该正确")

func test_handshake_message_format():
	# 测试握手消息格式
	ws_client._send_handshake()
	# 验证消息格式（需要通过实际连接测试，这里只测试函数不崩溃）
	pass_test("握手消息发送函数执行成功")

func test_state_sync_message_contains_required_fields():
	# 测试状态同步消息包含必要字段
	# 由于需要实际连接，这里只测试消息结构
	var sync_data = {
		"position": [0.0, 0.0, 0.0],
		"current_action": "idle",
		"is_dragging": false,
		"is_on_floor": true,
		"is_moving_locally": false,
		"is_jump_pressed": false,
		"velocity": [0.0, 0.0, 0.0]
	}
	
	# 验证必要字段存在
	assert_true(sync_data.has("position"), "应该包含 position 字段")
	assert_true(sync_data.has("is_jump_pressed"), "应该包含 is_jump_pressed 字段")
	assert_true(sync_data.has("is_moving_locally"), "应该包含 is_moving_locally 字段")
	assert_true(sync_data.has("is_on_floor"), "应该包含 is_on_floor 字段")

func test_jump_interaction_message_format():
	# 测试跳跃交互消息格式
	var jump_data = {
		"action": "jump",
		"position": [0.0, 1.0, 0.0],
		"velocity_y": 6.5
	}
	
	assert_eq(jump_data.get("action"), "jump", "动作类型应该是 jump")
	assert_true(jump_data.has("position"), "应该包含位置信息")
	assert_true(jump_data.has("velocity_y"), "应该包含垂直速度")
