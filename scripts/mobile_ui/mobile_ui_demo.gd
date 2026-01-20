class_name MobileUIDemo
extends Node3D

# 演示场景配置
@export var demo_mode: String = "form"  # form, button, text, list, multi_panel
@export var auto_connect: bool = true
@export var demo_websocket_url: String = "ws://localhost:8080"

@onready var mobile_ui_controller: Node = $MobileUIController
@onready var camera: Camera3D = $Camera3D

# 演示数据
var demo_panels: Dictionary = {}

func _ready():
    _setup_demo()
    if auto_connect:
        _start_demo_connection()

func _setup_demo():
    # 设置相机
    if camera:
        camera.position = Vector3(0, 1, 3)
        camera.look_at(Vector3.ZERO)

    # 连接信号
    if mobile_ui_controller:
        mobile_ui_controller.mobile_connected.connect(_on_mobile_connected)
        mobile_ui_controller.mobile_disconnected.connect(_on_mobile_disconnected)
        mobile_ui_controller.ui_panel_created.connect(_on_panel_created)
        mobile_ui_controller.interaction_received.connect(_on_interaction_received)

func _start_demo_connection():
    if mobile_ui_controller:
        mobile_ui_controller.websocket_url = demo_websocket_url
        mobile_ui_controller.connect_to_mobile()

func _create_demo_panels():
    match demo_mode:
        "form":
            _create_form_demo()
        "button":
            _create_button_demo()
        "text":
            _create_text_demo()
        "list":
            _create_list_demo()
        "multi_panel":
            _create_multi_panel_demo()

func _create_form_demo():
    var form_config = {
        "type": "form",
        "size": Vector2(400, 500),
        "position": Vector3(-1, 1, 0),
        "scale": Vector3(0.08, 0.08, 0.08),
        "content": {
            "title": "用户设置表单",
            "fields": [
                {
                    "label": "用户名",
                    "input_type": "text",
                    "value": "player123",
                    "placeholder": "请输入用户名"
                },
                {
                    "label": "年龄",
                    "input_type": "number",
                    "value": 25,
                    "min": 1,
                    "max": 120
                },
                {
                    "label": "邮箱",
                    "input_type": "text",
                    "value": "user@example.com",
                    "placeholder": "请输入邮箱地址"
                },
                {
                    "label": "启用通知",
                    "input_type": "checkbox",
                    "checked": true
                },
                {
                    "label": "难度等级",
                    "input_type": "select",
                    "options": ["简单", "普通", "困难", "专家"],
                    "selected": 1
                }
            ],
            "buttons": [
                {"text": "保存设置", "action": "save"},
                {"text": "重置", "action": "reset"},
                {"text": "取消", "action": "cancel"}
            ]
        }
    }

    mobile_ui_controller.create_mobile_ui_panel("settings_form", form_config)

func _create_button_demo():
    var button_panel_config = {
        "type": "container",
        "size": Vector2(300, 400),
        "position": Vector3(1, 1, 0),
        "scale": Vector3(0.08, 0.08, 0.08),
        "content": {
            "container_type": "vbox",
            "children": [
                {
                    "type": "text",
                    "text": "按钮演示面板",
                    "font_size": 16
                },
                {
                    "type": "button",
                    "text": "播放音乐",
                    "style": {"color": "#4CAF50", "font_size": 14}
                },
                {
                    "type": "button",
                    "text": "暂停",
                    "style": {"color": "#FF9800", "font_size": 14}
                },
                {
                    "type": "button",
                    "text": "停止",
                    "style": {"color": "#F44336", "font_size": 14}
                },
                {
                    "type": "slider",
                    "min": 0,
                    "max": 100,
                    "value": 50
                }
            ]
        }
    }

    mobile_ui_controller.create_mobile_ui_panel("button_demo", button_panel_config)

func _create_text_demo():
    var text_panel_config = {
        "type": "container",
        "size": Vector2(500, 400),
        "position": Vector3(0, 1.5, -1),
        "scale": Vector3(0.06, 0.06, 0.06),
        "content": {
            "container_type": "vbox",
            "children": [
                {
                    "type": "text",
                    "text": "[b][color=#4CAF50]3D UI 文本演示[/color][/b]\n\n这是Godot 3D UI系统的一个演示。",
                    "font_size": 14,
                    "scrollable": true
                },
                {
                    "type": "text",
                    "text": "[i]支持富文本格式[/i]\n• [color=#2196F3]蓝色文字[/color]\n• [color=#FF5722]橙色文字[/color]\n• [u]下划线[/u]\n• [s]删除线[/s]",
                    "font_size": 12
                }
            ]
        }
    }

    mobile_ui_controller.create_mobile_ui_panel("text_demo", text_panel_config)

func _create_list_demo():
    var list_panel_config = {
        "type": "list",
        "size": Vector2(350, 500),
        "position": Vector3(-1.5, 1, 0.5),
        "scale": Vector3(0.07, 0.07, 0.07),
        "content": {
            "items": [
                {
                    "title": "任务1: 探索森林",
                    "description": "寻找隐藏的宝藏",
                    "icon": "res://icon.svg"
                },
                {
                    "title": "任务2: 击败怪物",
                    "description": "挑战强大的敌人",
                    "icon": "res://icon.svg"
                },
                {
                    "title": "任务3: 收集资源",
                    "description": "收集稀有材料",
                    "icon": "res://icon.svg"
                },
                {
                    "title": "任务4: 建造基地",
                    "description": "建设你的家园",
                    "icon": "res://icon.svg"
                },
                {
                    "title": "任务5: 升级装备",
                    "description": "提升你的实力",
                    "icon": "res://icon.svg"
                }
            ]
        }
    }

    mobile_ui_controller.create_mobile_ui_panel("list_demo", list_panel_config)

func _create_multi_panel_demo():
    # 创建多个演示面板
    var panel_configs = [
        {
            "id": "control_panel",
            "config": {
                "type": "container",
                "size": Vector2(300, 200),
                "position": Vector3(0, 2, 0),
                "scale": Vector3(0.08, 0.08, 0.08),
                "content": {
                    "container_type": "vbox",
                    "children": [
                        {"type": "text", "text": "[b]控制面板[/b]", "font_size": 16},
                        {"type": "button", "text": "创建设置表单"},
                        {"type": "button", "text": "创建按钮面板"},
                        {"type": "button", "text": "创建文本面板"},
                        {"type": "button", "text": "创建列表面板"}
                    ]
                }
            }
        },
        {
            "id": "info_panel",
            "config": {
                "type": "container",
                "size": Vector2(400, 150),
                "position": Vector3(2, 1.5, 1),
                "scale": Vector3(0.06, 0.06, 0.06),
                "content": {
                    "container_type": "vbox",
                    "children": [
                        {"type": "text", "text": "[b]系统信息[/b]", "font_size": 14},
                        {"type": "text", "text": "连接状态: 未连接", "font_size": 12},
                        {"type": "text", "text": "活动面板: 0", "font_size": 12},
                        {"type": "text", "text": "FPS: --", "font_size": 12}
                    ]
                }
            }
        }
    ]

    for panel_data in panel_configs:
        mobile_ui_controller.create_mobile_ui_panel(panel_data.id, panel_data.config)

# 事件处理
func _on_mobile_connected(device_info: Dictionary):
    print("移动设备已连接: ", device_info)
    _create_demo_panels()
    _update_info_panel("连接状态: 已连接")

func _on_mobile_disconnected():
    print("移动设备已断开连接")
    _update_info_panel("连接状态: 未连接")

func _on_panel_created(panel_id: String, panel: Node3D):
    print("面板已创建: ", panel_id)
    demo_panels[panel_id] = panel
    _update_info_panel("活动面板: " + str(demo_panels.size()))

func _on_interaction_received(panel_id: String, event_type: String, event_data: Dictionary):
    print("收到交互事件: ", panel_id, " -> ", event_type, " : ", event_data)

    # 处理演示特定的交互
    match panel_id:
        "control_panel":
            _handle_control_panel_interaction(event_type, event_data)
        "settings_form":
            _handle_form_interaction(event_type, event_data)

func _handle_control_panel_interaction(event_type: String, event_data: Dictionary):
    if event_type == "button_click":
        var button_text = event_data.get("button_text", "")
        match button_text:
            "创建设置表单":
                _create_form_demo()
            "创建按钮面板":
                _create_button_demo()
            "创建文本面板":
                _create_text_demo()
            "创建列表面板":
                _create_list_demo()

func _handle_form_interaction(event_type: String, event_data: Dictionary):
    if event_type == "form_submit":
        print("表单提交: ", event_data)
        # 这里可以处理表单数据

func _update_info_panel(status_text: String):
    if demo_panels.has("info_panel"):
        # 更新信息面板内容
        var update_data = {
            "content": {
                "children[1].text": status_text,
                "children[3].text": "FPS: " + str(Engine.get_frames_per_second())
            }
        }
        mobile_ui_controller.update_mobile_ui_panel("info_panel", update_data)

func _process(delta):
    # 每秒更新一次FPS显示
    if demo_panels.has("info_panel") and Engine.get_frames_per_second() % 30 == 0:  # 大约每秒更新一次
        _update_info_panel("FPS: " + str(Engine.get_frames_per_second()))

# 演示控制方法
func switch_demo_mode(new_mode: String):
    demo_mode = new_mode

    # 清除现有面板
    for panel_id in demo_panels.keys():
        mobile_ui_controller.remove_mobile_ui_panel(panel_id)
    demo_panels.clear()

    # 创建新演示
    _create_demo_panels()

func get_demo_stats() -> Dictionary:
    return {
        "mode": demo_mode,
        "active_panels": demo_panels.size(),
        "connection_status": "connected" if mobile_ui_controller.is_connected else "disconnected",
        "websocket_url": demo_websocket_url
    }

func toggle_connection():
    if mobile_ui_controller.is_connected:
        mobile_ui_controller.disconnect_mobile()
    else:
        mobile_ui_controller.connect_to_mobile()

# 输入处理（用于演示控制）
func _input(event):
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_1:
                switch_demo_mode("form")
            KEY_2:
                switch_demo_mode("button")
            KEY_3:
                switch_demo_mode("text")
            KEY_4:
                switch_demo_mode("list")
            KEY_5:
                switch_demo_mode("multi_panel")
            KEY_C:
                toggle_connection()
            KEY_R:
                # 重置演示
                switch_demo_mode(demo_mode)