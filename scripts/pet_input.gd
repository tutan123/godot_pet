extends Node

## pet_input.gd
## 输入处理模块：负责获取和处理用户输入

const PetData = preload("res://scripts/pet_data.gd")
const PetLogger = preload("res://scripts/logger.gd")

## 获取输入数据
func get_input_data():
	var data = PetData.InputData.new()
	var focus_owner = get_viewport().gui_get_focus_owner()
	data.is_typing = focus_owner is LineEdit
	
	if not data.is_typing:
		data.direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		data.is_running = Input.is_key_pressed(KEY_SHIFT)
		data.jump_pressed = Input.is_action_pressed("jump")
		data.jump_just_pressed = Input.is_action_just_pressed("jump")
	
	return data
