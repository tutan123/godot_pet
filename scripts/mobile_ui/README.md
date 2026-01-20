# Godot 3D Mobile UI System

这是一个在Godot中实现3D手机UI集成的完整解决方案，允许在虚拟3D世界中显示和交互手机设备的UI界面。

## 功能特性

- **3D UI渲染**: 使用SubViewport和Sprite3D将2D UI渲染到3D空间
- **实时交互**: 支持点击、拖拽、多指操作等完整交互
- **WebSocket通信**: 与手机设备实时同步UI状态
- **组件化设计**: 可扩展的UI组件系统
- **手势识别**: 支持捏合、旋转、滑动等手势操作
- **状态同步**: 双向状态同步，支持增量更新

## 文件结构

```
mobile_ui/
├── mobile_ui_controller.gd      # 主控制器
├── ui_renderer_3d.gd           # 3D UI渲染器
├── interaction_handler.gd      # 交互处理器
├── gesture_recognizer.gd       # 手势识别器
├── state_synchronizer.gd       # 状态同步器
├── ui_component_factory.gd     # UI组件工厂
├── mobile_ui_demo.gd          # 演示脚本
└── ui_components/             # UI组件目录
    └── (组件实现文件)
```

## 快速开始

### 1. 添加系统到场景

1. 创建一个新的3D场景
2. 添加一个Node3D节点作为MobileUIController
3. 将`mobile_ui_controller.gd`脚本附加到该节点
4. 系统会自动初始化所有子组件

### 2. 配置连接

```gdscript
@onready var mobile_ui = $MobileUIController

func _ready():
    # 设置WebSocket URL
    mobile_ui.websocket_url = "ws://你的手机IP:8080"

    # 连接到手机设备
    mobile_ui.connect_to_mobile()
```

### 3. 创建UI面板

```gdscript
func create_example_panel():
    var panel_config = {
        "type": "form",
        "size": Vector2(400, 300),
        "position": Vector3(0, 1, 2),
        "scale": Vector3(0.1, 0.1, 0.1),
        "content": {
            "title": "示例表单",
            "fields": [
                {
                    "label": "用户名",
                    "input_type": "text",
                    "value": "player1"
                }
            ]
        }
    }

    mobile_ui.create_mobile_ui_panel("example_panel", panel_config)
```

## API参考

### MobileUIController

#### 属性
- `websocket_url`: WebSocket服务器地址
- `ui_scale`: UI默认缩放
- `interaction_distance`: 交互距离
- `auto_reconnect`: 自动重连

#### 方法
- `connect_to_mobile(url)`: 连接到手机设备
- `disconnect_mobile()`: 断开连接
- `create_mobile_ui_panel(panel_id, config)`: 创建UI面板
- `update_mobile_ui_panel(panel_id, updates)`: 更新UI面板
- `remove_mobile_ui_panel(panel_id)`: 删除UI面板

#### 信号
- `mobile_connected(device_info)`: 手机设备连接成功
- `mobile_disconnected()`: 手机设备断开连接
- `ui_panel_created(panel_id, panel)`: UI面板创建完成
- `interaction_received(panel_id, event_type, event_data)`: 收到交互事件

### UI配置格式

#### 面板配置
```json
{
    "type": "form|button|text|list|container",
    "size": [width, height],
    "position": [x, y, z],
    "scale": [x, y, z],
    "rotation": [x, y, z],
    "content": {
        // 内容配置，取决于type
    }
}
```

#### 表单配置
```json
{
    "title": "表单标题",
    "fields": [
        {
            "label": "字段标签",
            "input_type": "text|number|password|checkbox|select",
            "value": "默认值",
            "placeholder": "占位符",
            "options": ["选项1", "选项2"] // 对于select类型
        }
    ],
    "buttons": [
        {"text": "按钮文本", "action": "动作名称"}
    ]
}
```

## 演示场景

运行`mobile_ui_demo.gd`脚本来查看完整演示：

- **按键1**: 表单演示
- **按键2**: 按钮演示
- **按键3**: 文本演示
- **按键4**: 列表演示
- **按键5**: 多面板演示
- **按键C**: 切换连接状态
- **按键R**: 重置当前演示

## 手机端要求

手机端需要实现WebSocket服务器，支持以下消息格式：

### 连接建立
```json
{
    "type": "connect",
    "client_type": "godot_3d_ui",
    "capabilities": ["ui_rendering", "interaction", "gesture_support"]
}
```

### UI面板创建
```json
{
    "type": "create_panel",
    "panel_id": "panel_name",
    "config": {
        // 面板配置
    }
}
```

### 交互事件
```json
{
    "type": "interaction",
    "panel_id": "panel_name",
    "event_type": "click|drag|gesture",
    "event_data": {
        // 事件数据
    }
}
```

## 性能优化

1. **视锥剔除**: 只渲染可见的UI面板
2. **空间分区**: 使用网格优化碰撞检测
3. **纹理压缩**: 使用适当的纹理压缩格式
4. **对象池**: 复用UI组件对象
5. **增量同步**: 只同步状态变化
6. **逻辑投屏**: 支持从外部 React/Web 应用通过 WebSocket 实时投影 UI 布局到 3D 空间

## 逻辑投屏 (Logic Mirroring) 快速指南

你可以将现有的 Web 项目（如 `q_llm_pet`）作为 UI 数据源投影到 Godot 中：

1. **Web 端发送同步消息**:
   在你的 React/JS 代码中定期发送以下格式的消息：
   ```json
   {
     "type": "ui_sync",
     "data": {
       "panel_id": "robot_monitor",
       "config": {
         "type": "container",
         "content": {
           "container_type": "vbox",
           "children": [
             { "type": "text", "text": "Hello from React!" }
           ]
         }
       }
     }
   }
   ```

2. **Godot 端自动处理**:
   `MobileUIController` 会自动捕获 `ui_sync` 消息，并在角色面前动态创建/更新对应的 3D UI 卡片。

## 故障排除

### 常见问题

1. **UI不显示**
   - 检查SubViewport大小设置
   - 确认Sprite3D的纹理已正确设置
   - 检查面板位置是否在相机视锥内

2. **交互无响应**
   - 确认InteractionHandler已正确初始化
   - 检查碰撞层设置
   - 验证射线检测参数

3. **WebSocket连接失败**
   - 检查网络连接
   - 确认WebSocket服务器正在运行
   - 验证URL格式

### 调试信息

启用调试模式查看详细日志：

```gdscript
mobile_ui.debug_mode = true
```

## 扩展开发

### 添加新UI组件

1. 在`ui_component_factory.gd`中添加创建方法
2. 实现组件的交互逻辑
3. 添加相应的配置解析

### 自定义手势

在`gesture_recognizer.gd`中添加新的手势识别逻辑：

```gdscript
func recognize_custom_gesture(touch_data: Dictionary):
    # 实现自定义手势识别
    pass
```

### 网络协议扩展

修改`mobile_ui_controller.gd`中的消息处理逻辑以支持新的消息类型。

## 许可证

本项目采用MIT许可证，详见项目根目录的LICENSE文件。