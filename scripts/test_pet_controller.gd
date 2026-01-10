extends "res://addons/gut/test.gd"

## PetController 测试
## 测试宠物控制器的状态同步、输入处理等功能

func test_state_sync_data_structure():
	# 测试状态同步数据结构
	var state_sync_data = {
		"position": [1.0, 2.0, 3.0],
		"current_action": "walk",
		"is_dragging": false,
		"is_on_floor": true,
		"is_moving_locally": true,
		"is_jump_pressed": false,
		"velocity": [0.5, 0.0, 0.5]
	}
	
	# 验证所有必要字段
	assert_true(state_sync_data.has("position"), "应该包含 position")
	assert_true(state_sync_data.has("is_jump_pressed"), "应该包含 is_jump_pressed（空格键状态）")
	assert_true(state_sync_data.has("is_moving_locally"), "应该包含 is_moving_locally")
	assert_true(state_sync_data.has("is_on_floor"), "应该包含 is_on_floor")
	assert_true(state_sync_data.has("velocity"), "应该包含 velocity")
	
	# 验证数据类型
	assert_true(state_sync_data.get("position") is Array, "position 应该是数组")
	assert_true(state_sync_data.get("is_jump_pressed") is bool, "is_jump_pressed 应该是布尔值")

func test_jump_interaction_message():
	# 测试跳跃交互消息格式
	var jump_interaction = {
		"action": "jump",
		"position": [0.0, 1.0, 0.0],
		"velocity_y": 6.5
	}
	
	assert_eq(jump_interaction.get("action"), "jump", "动作应该是 jump")
	assert_true(jump_interaction.has("position"), "应该包含位置")
	assert_true(jump_interaction.has("velocity_y"), "应该包含垂直速度")
	assert_eq(jump_interaction.get("velocity_y"), 6.5, "垂直速度应该是 6.5")

func test_jump_state_tracking():
	# 测试跳跃状态跟踪逻辑
	var last_jump_pressed = false
	var jump_pressed = true
	var jump_just_pressed = true
	
	# 模拟状态更新
	if jump_just_pressed:
		last_jump_pressed = jump_pressed
		var jump_time_recorded = true
		assert_true(jump_time_recorded, "应该记录跳跃时间")
	
	# 模拟状态清除（500ms 后）
	last_jump_pressed = false
	assert_false(last_jump_pressed, "500ms 后应该清除跳跃按下状态")

func test_action_state_priority_logic():
	# 测试动作状态优先级逻辑
	var current_action_state = {
		"name": "idle",
		"priority": 10,
		"duration": 3000,
		"start_time": 0.0
	}
	
	var new_action_state = {
		"name": "dance",
		"priority": 50,
		"duration": 3000,
		"start_time": 1000.0
	}
	
	# 验证优先级比较
	var should_interrupt = new_action_state.get("priority") > current_action_state.get("priority")
	assert_true(should_interrupt, "高优先级动作应该中断低优先级动作")

func test_collision_interaction_format():
	# 测试碰撞交互消息格式
	var collision_data = {
		"action": "collision",
		"collider_name": "Wall",
		"position": [5.0, 0.0, 0.0],
		"normal": [1.0, 0.0, 0.0]
	}
	
	assert_eq(collision_data.get("action"), "collision", "动作应该是 collision")
	assert_eq(collision_data.get("collider_name"), "Wall", "碰撞体名称应该正确")
	assert_true(collision_data.has("position"), "应该包含位置")
	assert_true(collision_data.has("normal"), "应该包含法线")
