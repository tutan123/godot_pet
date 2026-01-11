# Godot 客户端产品技术设计文档

> **文档版本**: v1.0  
> **更新日期**: 2025-01  
> **适用范围**: Godot 3D 萌宠客户端

## 目录

1. [概述](#概述)
2. [系统架构](#系统架构)
3. [BlendTree 动画系统](#blendtree-动画系统)
4. [WebSocket 通信系统](#websocket-通信系统)
5. [3D 系统](#3d-系统)
6. [物理系统](#物理系统)
7. [相机系统](#相机系统)
8. [UI 系统](#ui-系统)
9. [数据流与状态管理](#数据流与状态管理)
10. [关键流程时序图](#关键流程时序图)

---

## 概述

### 项目定位

Godot 客户端是 3D 萌宠系统的**表现层**，负责：

- **3D 渲染**：高质量的 3D 模型渲染和动画表现
- **物理交互**：基于 Godot 物理引擎的实时物理响应
- **用户输入**：键盘、鼠标交互的直接响应
- **网络通信**：与服务端（JS 行为树）的双向 WebSocket 通信

### 核心设计理念

1. **参数驱动动画**：使用 BlendTree 实现参数驱动的动画混合
2. **输入输出隔离**：传感器数据（Sensor）与执行器指令（Actuator）分离
3. **基础移动本地控制**：`IDLE`/`WALK`/`RUN` 完全由客户端控制
4. **特殊动作服务端决策**：`JUMP`/`WAVE`/`DANCE` 等由服务端决策下发
5. **马尔可夫决策响应**：每一帧根据当前状态响应，无历史依赖

### 技术栈

- **引擎**: Godot 4.x
- **脚本语言**: GDScript
- **动画系统**: AnimationTree + BlendTree
- **物理引擎**: Godot CharacterBody3D
- **通信协议**: WebSocket (JSON)
- **渲染**: 3D Forward Rendering

---

## 系统架构

### 整体架构图

```mermaid
graph TB
    subgraph "JS 服务端 (云端大脑)"
        A[WebSocket Server] --> B[Behavior Tree Engine]
        B --> C[LLM Service]
        B --> D[Blackboard System]
        D -->|Sensor Data| B
        B -->|Actuator Output| A
    end
    
    subgraph "Godot 客户端 (表现层)"
        E[WebSocket Client] --> F[Pet Controller]
        F --> G[Animation Tree<br/>BlendTree]
        F --> H[CharacterBody3D<br/>Physics]
        F --> I[Camera System]
        J[Input System] --> F
        K[UI System] --> E
        G --> L[Skeletal Animation]
        G --> M[Procedural Animation]
        H --> N[Collision Detection]
    end
    
    A <-->|WebSocket JSON| E
    F -->|state_sync<br/>interaction| E
    E -->|bt_output<br/>status_update| F
    
    classDef server fill:#ffcccc,stroke:#333,stroke-width:2px
    classDef client fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef animation fill:#ccccff,stroke:#333,stroke-width:2px
    
    class A,B,C,D server
    class E,F,H,I,J,K,N client
    class G,L,M animation
```

### 模块职责划分

| 模块 | 职责 | 核心技术 |
|------|------|---------|
| **PetController** | 核心控制器，协调各子系统 | GDScript |
| **AnimationTree** | 参数驱动的动画混合 | BlendTree |
| **WebSocketClient** | 网络通信管理 | WebSocket |
| **CharacterBody3D** | 物理运动与碰撞 | Physics Engine |
| **CameraSystem** | 第三人称相机控制 | SpringArm3D |
| **UISystem** | 用户界面与输入 | Control Nodes |

### 场景树结构

```mermaid
graph TD
    A[Main Scene] --> B[Pet CharacterBody3D]
    A --> C[WebSocketClient Node]
    A --> D[CameraRig Node3D]
    A --> E[UI Control]
    A --> F[WorldEnvironment]
    A --> G[Lighting System]
    
    B --> B1[MeshInstance3D<br/>3D Model]
    B --> B2[AnimationTree<br/>BlendTree]
    B --> B3[CollisionShape3D]
    B --> B4[RayCast3D<br/>Ground Check]
    
    D --> D1[SpringArm3D]
    D1 --> D2[Camera3D]
    D --> D3[CameraController Script]
    
    E --> E1[Panel]
    E1 --> E2[VBoxContainer]
    E2 --> E3[RichTextLabel<br/>Chat Log]
    E2 --> E4[HBoxContainer]
    E4 --> E5[LineEdit<br/>Input]
    E4 --> E6[Button<br/>Send]
    
    classDef scene fill:#ffffcc,stroke:#333,stroke-width:2px
    classDef pet fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef camera fill:#ffccff,stroke:#333,stroke-width:2px
    classDef ui fill:#ccccff,stroke:#333,stroke-width:2px
    
    class A,F,G scene
    class B,B1,B2,B3,B4 pet
    class D,D1,D2,D3 camera
    class E,E1,E2,E3,E4,E5,E6 ui
```

---

## BlendTree 动画系统

### 架构设计

当前系统使用 **BlendTree（混合树）** 而非 StateMachine（状态机），实现参数驱动的动画系统。

#### 为什么使用 BlendTree？

1. **参数驱动**：与服务端黑板系统的参数化思维完美匹配
2. **平滑混合**：参数连续变化带来自然的动画过渡
3. **多维混合**：避免状态爆炸，支持灵活扩展
4. **声明式状态**：参数持续生效，符合声明式通信协议

### BlendTree 结构图

```mermaid
graph TD
    A[AnimationTree Root] --> B[BlendTree]
    
    B --> C[Locomotion<br/>BlendSpace1D]
    C --> C1[idle<br/>pos: 0.0]
    C --> C2[walk<br/>pos: 0.3]
    C --> C3[run<br/>pos: 1.0]
    
    B --> D[JumpBlend<br/>Blend2]
    D --> D1[jump animation<br/>Input 0]
    D --> D2[Locomotion Output<br/>Input 1]
    
    B --> E[WaveBlend<br/>Blend2]
    E --> E1[wave animation<br/>Input 0]
    E --> E2[JumpBlend Output<br/>Input 1]
    
    B --> F[EnergyBlend<br/>BlendSpace1D<br/>Future]
    F --> F1[tired<br/>pos: 0.0]
    F --> F2[energetic<br/>pos: 1.0]
    
    G[Parameters] --> C
    G --> D
    G --> E
    G --> F
    
    G --> G1[locomotion/blend_position<br/>0.0-1.0]
    G --> G2[jump_blend/blend_amount<br/>0.0-1.0]
    G --> G3[wave_blend/blend_amount<br/>0.0-1.0]
    G --> G4[energy_blend/blend_position<br/>0.0-1.0]
    
    classDef blend fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef param fill:#ffffcc,stroke:#333,stroke-width:2px
    classDef anim fill:#ffcccc,stroke:#333,stroke-width:2px
    
    class C,D,E,F blend
    class G,G1,G2,G3,G4 param
    class C1,C2,C3,D1,E1,F1,F2 anim
```

### 参数控制规范

#### 基础移动参数（Locomotion）

**参数路径**: `parameters/locomotion/blend_position`

**值范围**: `0.0` - `1.0`

**映射关系**:
- `0.0` → `idle` 动画
- `0.3` → `walk` 动画
- `1.0` → `run` 动画
- `0.0-1.0` 之间 → 自动混合

**代码实现**:
```gdscript
func _apply_blendtree_state(state: AnimState) -> void:
    match state:
        AnimState.IDLE:
            animation_tree.set("parameters/locomotion/blend_position", 0.0)
        AnimState.WALK:
            animation_tree.set("parameters/locomotion/blend_position", 0.3)
        AnimState.RUN:
            animation_tree.set("parameters/locomotion/blend_position", 1.0)
```

#### 离散动作参数（Overlay）

**参数路径**: `parameters/{action}_blend/blend_amount`

**值范围**: `0.0` - `1.0`

**含义**:
- `0.0` → 隐藏该动作，显示下层动作
- `1.0` → 显示该动作，覆盖下层动作

**支持的动作**:
- `jump` → `parameters/jump_blend/blend_amount`
- `wave` → `parameters/wave_blend/blend_amount`

**代码实现**:
```gdscript
func _switch_anim(action_name: String) -> void:
    match action_name:
        "jump":
            animation_tree.set("parameters/jump_blend/blend_amount", 1.0)
        "wave":
            animation_tree.set("parameters/wave_blend/blend_amount", 1.0)
            # 完成后需要清除
```

### 动画类型

#### 1. 骨骼动画（Skeletal Animation）

**来源**: 3D 模型文件（.glb/.fbx）

**动画列表**:
- `idle` - 待机动画
- `walk` - 走路动画
- `run` - 跑步动画
- `jump` - 跳跃动画
- `wave` - 挥手动画

**特点**: 预制的关键帧动画，由美术制作

#### 2. 程序化动画（Procedural Animation）

**实现方式**: 代码实时修改模型的 Transform

**支持的动作**:
- `SPIN` - 自转
- `BOUNCE` - 弹跳
- `FLY` - 悬浮飞行
- `ROLL` - 侧滚

**代码示例**:
```gdscript
func _process_procedural_animation(delta: float) -> void:
    match proc_anim_type:
        ProcAnimType.SPIN:
            rotation.y += spin_speed * delta
        ProcAnimType.BOUNCE:
            var bounce_offset = sin(proc_time * bounce_frequency) * bounce_amplitude
            position.y = base_y + bounce_offset
```

### BlendTree 优势

```mermaid
graph LR
    A[BlendTree 优势] --> B[参数驱动<br/>与服务端匹配]
    A --> C[平滑混合<br/>自然过渡]
    A --> D[多维扩展<br/>避免状态爆炸]
    A --> E[声明式状态<br/>持续生效]
    
    B --> B1[energy: 75<br/>直接映射参数]
    C --> C1[speed: 0.5<br/>自动混合 walk+run]
    D --> D1[4个参数<br/>而非72个状态]
    E --> E1[参数设置即生效<br/>无需状态转换]
    
    classDef advantage fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef detail fill:#ffffcc,stroke:#333,stroke-width:2px
    
    class A,B,C,D,E advantage
    class B1,C1,D1,E1 detail
```

---

## WebSocket 通信系统

### 通信架构

```mermaid
sequenceDiagram
    participant G as Godot Client
    participant WS as WebSocket
    participant S as JS Server
    
    Note over G,S: 连接建立阶段
    G->>WS: connect(ws://localhost:8080)
    WS->>S: WebSocket Connection
    G->>S: handshake {client_type, version, platform}
    S-->>G: handshake_ack
    
    Note over G,S: 运行阶段 - 客户端上报
    loop 每帧/每100ms
        G->>S: state_sync {position, is_moving_locally, ...}
    end
    
    G->>S: interaction {action: click, position}
    G->>S: interaction {action: drag_start, position}
    G->>S: interaction {action: drag_end, position}
    G->>S: user_input {text: "跳个舞吧"}
    
    Note over G,S: 运行阶段 - 服务端下发
    S->>G: bt_output {actionState: {name, priority, duration}}
    S->>G: status_update {energy, boredom}
    S->>G: chat {content, role}
    S->>G: move_to {target: [x,y,z]}
```

### 消息协议

#### 客户端 → 服务端

##### 1. 握手消息（handshake）

```json
{
  "type": "handshake",
  "timestamp": 1234567890,
  "data": {
    "client_type": "godot_robot",
    "platform": "Windows",
    "version": "1.0"
  }
}
```

##### 2. 状态同步（state_sync）

**发送频率**: 每帧或每 100ms（10Hz）

```json
{
  "type": "state_sync",
  "timestamp": 1234567890,
  "data": {
    "position": [0.0, -1.0, 0.0],
    "current_action": "walk",
    "is_dragging": false,
    "is_on_floor": true,
    "is_moving_locally": true,
    "is_jump_pressed": false,
    "velocity": [1.5, 0.0, 0.0]
  }
}
```

**字段说明**:

| 字段 | 类型 | 说明 |
|-----|------|------|
| `position` | Array[Float] | 3D 坐标 [x, y, z] |
| `is_moving_locally` | Boolean | **关键**: 是否正在本地控制移动（WASD） |
| `is_jump_pressed` | Boolean | 是否正在按跳跃键 |
| `is_dragging` | Boolean | 是否正在被拖拽 |
| `velocity` | Array[Float] | 速度向量 [x, y, z] |

##### 3. 交互事件（interaction）

```json
{
  "type": "interaction",
  "timestamp": 1234567890,
  "data": {
    "action": "click",
    "position": [0.0, -1.0, 0.0]
  }
}
```

**支持的动作**: `click`, `drag_start`, `drag_end`

##### 4. 用户输入（user_input）

```json
{
  "type": "user_input",
  "timestamp": 1234567890,
  "data": {
    "text": "跳个舞吧"
  }
}
```

#### 服务端 → 客户端

##### 1. 行为树输出（bt_output）

```json
{
  "type": "bt_output",
  "timestamp": 1234567890,
  "data": {
    "actionState": {
      "name": "JUMP",
      "priority": 50,
      "duration": 1000,
      "interruptible": true,
      "timestamp": 1234567890
    }
  }
}
```

**字段说明**:

| 字段 | 类型 | 说明 |
|-----|------|------|
| `actionState.name` | String | 动作名称（JUMP/WAVE/DANCE 等） |
| `actionState.priority` | Integer | 优先级（数值越大优先级越高） |
| `actionState.duration` | Integer | 持续时间（毫秒） |
| `actionState.interruptible` | Boolean | 是否可中断 |

**重要规则**: 基础移动动作（`IDLE`/`WALK`/`RUN`）不会通过 `bt_output` 下发

##### 2. 状态更新（status_update）

```json
{
  "type": "status_update",
  "timestamp": 1234567890,
  "data": {
    "energy": 75,
    "boredom": 25
  }
}
```

##### 3. 聊天消息（chat）

```json
{
  "type": "chat",
  "timestamp": 1234567890,
  "data": {
    "content": "好的，我来跳舞给你看！",
    "role": "assistant"
  }
}
```

### WebSocket 客户端实现

```mermaid
graph TD
    A[WebSocketClient] --> B[连接管理]
    A --> C[消息发送]
    A --> D[消息接收]
    A --> E[心跳机制]
    
    B --> B1[connect_to_server]
    B --> B2[disconnect_from_server]
    B --> B3[重连逻辑]
    
    C --> C1[send_message]
    C --> C2[_send_handshake]
    C --> C3[心跳发送]
    
    D --> D1[_process 轮询]
    D --> D2[_handle_json_message]
    D --> D3[message_received 信号]
    
    E --> E1[心跳定时器]
    E --> E2[连接状态检测]
    
    classDef module fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef function fill:#ffffcc,stroke:#333,stroke-width:2px
    
    class A,B,C,D,E module
    class B1,B2,B3,C1,C2,C3,D1,D2,D3,E1,E2 function
```

### 通信流程图

```mermaid
flowchart TD
    A[Godot Client] -->|1. Connect| B[WebSocket Server]
    A -->|2. Handshake| B
    B -->|3. Handshake ACK| A
    
    A -->|4. state_sync| B
    A -->|5. interaction| B
    A -->|6. user_input| B
    
    B -->|7. bt_output| A
    B -->|8. status_update| A
    B -->|9. chat| A
    
    A -->|10. Process Messages| C[PetController]
    C -->|11. Apply Actions| D[AnimationTree]
    C -->|12. Update Physics| E[CharacterBody3D]
    
    classDef client fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef server fill:#ffcccc,stroke:#333,stroke-width:2px
    classDef system fill:#ccccff,stroke:#333,stroke-width:2px
    
    class A,C,D,E client
    class B server
    class C,D,E system
```

---

## 3D 系统

### 场景结构

```mermaid
graph TD
    A[Main Scene] --> B[Pet CharacterBody3D]
    A --> C[WorldEnvironment]
    A --> D[DirectionalLight3D]
    A --> E[OmniLight3D]
    
    B --> B1[Player Node3D]
    B1 --> B11[MeshInstance3D<br/>3D Model]
    B1 --> B12[Skeleton3D]
    
    B --> B2[AnimationTree]
    B2 --> B21[AnimationPlayer]
    
    B --> B3[CollisionShape3D<br/>CapsuleShape3D]
    B --> B4[RayCast3D<br/>Ground Check]
    
    C --> C1[Environment Resource]
    C1 --> C11[Background: Sky]
    C1 --> C12[Ambient Light]
    C1 --> C13[Tonemap: ACES]
    
    classDef scene fill:#ffffcc,stroke:#333,stroke-width:2px
    classDef pet fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef light fill:#ffcccc,stroke:#333,stroke-width:2px
    
    class A,C scene
    class B,B1,B11,B12,B2,B21,B3,B4 pet
    class D,E,C1,C11,C12,C13 light
```

### 渲染管线

```mermaid
graph LR
    A[3D Scene] --> B[Camera3D]
    B --> C[Culling]
    C --> D[Forward Rendering]
    D --> E[Lighting]
    E --> F[Shading]
    F --> G[Post Processing]
    G --> H[Viewport]
    
    I[Environment] --> E
    J[DirectionalLight] --> E
    K[OmniLight] --> E
    
    classDef pipeline fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef source fill:#ffffcc,stroke:#333,stroke-width:2px
    
    class A,B,C,D,E,F,G,H pipeline
    class I,J,K source
```

### 模型资源

**模型格式**: `.glb` / `.fbx`

**模型结构**:
- Mesh（网格）
- Skeleton（骨骼）
- Animations（动画）

**动画资源**:
- `idle` - 待机
- `walk` - 走路
- `run` - 跑步
- `jump` - 跳跃
- `wave` - 挥手

---

## 物理系统

### 物理架构

```mermaid
graph TD
    A[CharacterBody3D] --> B[物理属性]
    A --> C[碰撞检测]
    A --> D[地面检测]
    A --> E[移动逻辑]
    
    B --> B1[velocity: Vector3]
    B --> B2[gravity: float]
    B --> B3[move_and_slide]
    
    C --> C1[CollisionShape3D]
    C --> C2[碰撞响应]
    C --> C3[碰撞事件上报]
    
    D --> D1[RayCast3D]
    D --> D2[is_on_floor]
    D --> D3[地面跟随]
    
    E --> E1[本地输入移动]
    E --> E2[服务端指令移动]
    E --> E3[拖拽移动]
    
    classDef physics fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef detection fill:#ffffcc,stroke:#333,stroke-width:2px
    classDef movement fill:#ffcccc,stroke:#333,stroke-width:2px
    
    class A,B,B1,B2,B3 physics
    class C,C1,C2,C3,D,D1,D2,D3 detection
    class E,E1,E2,E3 movement
```

### 移动优先级

```mermaid
graph TD
    A[移动输入] --> B{优先级判断}
    
    B -->|最高| C[拖拽移动]
    B -->|高| D[本地键盘输入<br/>WASD]
    B -->|中| E[服务端指令移动<br/>move_to]
    B -->|低| F[物理重力]
    
    C --> G[直接设置位置]
    D --> H[velocity 计算]
    E --> I[target_position 插值]
    F --> J[gravity 应用]
    
    G --> K[move_and_slide]
    H --> K
    I --> K
    J --> K
    
    classDef priority fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef method fill:#ffffcc,stroke:#333,stroke-width:2px
    
    class A,B,C,D,E,F priority
    class G,H,I,J,K method
```

### 物理参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `walk_speed` | 3.0 | 走路速度（m/s） |
| `run_speed` | 7.0 | 跑步速度（m/s） |
| `jump_velocity` | 6.5 | 跳跃初速度（m/s） |
| `rotation_speed` | 12.0 | 旋转速度（rad/s） |
| `gravity` | 9.8 | 重力加速度（m/s²） |

---

## 相机系统

### 相机架构

```mermaid
graph TD
    A[CameraRig Node3D] --> B[SpringArm3D]
    B --> C[Camera3D]
    A --> D[CameraController Script]
    
    D --> E[目标跟随]
    D --> F[鼠标旋转]
    D --> G[滚轮缩放]
    D --> H[角度限制]
    
    E --> E1[跟随 Pet 位置]
    E --> E2[平滑插值]
    
    F --> F1[右键拖拽]
    F --> F2[水平旋转 Y]
    F --> F3[垂直旋转 X]
    
    G --> G1[滚轮上/下]
    G --> G2[调整 spring_length]
    G --> G3[min_zoom / max_zoom]
    
    H --> H1[俯仰角限制<br/>-80° ~ 20°]
    
    classDef camera fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef control fill:#ffffcc,stroke:#333,stroke-width:2px
    
    class A,B,C,D camera
    class E,F,G,H,E1,E2,F1,F2,F3,G1,G2,G3,H1 control
```

### 相机参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `mouse_sensitivity` | 0.3 | 鼠标灵敏度 |
| `zoom_speed` | 0.5 | 缩放速度 |
| `min_zoom` | 2.0 | 最小距离（m） |
| `max_zoom` | 12.0 | 最大距离（m） |
| `follow_speed` | 5.0 | 跟随速度 |
| `spring_length` | 5.0 | 弹簧臂长度（m） |
| `pitch_min` | -80.0 | 最小俯仰角（度） |
| `pitch_max` | 20.0 | 最大俯仰角（度） |

### 相机控制流程

```mermaid
flowchart TD
    A[用户输入] --> B{输入类型}
    
    B -->|鼠标右键拖拽| C[旋转控制]
    B -->|滚轮| D[缩放控制]
    B -->|物理更新| E[跟随目标]
    
    C --> C1[计算 rotation_y<br/>水平旋转]
    C --> C2[计算 rotation_x<br/>垂直旋转]
    C2 --> C3[角度限制<br/>clamp -80~20]
    
    D --> D1[调整 spring_length]
    D1 --> D2[距离限制<br/>clamp 2~12]
    
    E --> E1[获取目标位置]
    E1 --> E2[平滑插值跟随]
    
    C3 --> F[应用 Transform]
    D2 --> F
    E2 --> F
    
    F --> G[Camera3D 渲染]
    
    classDef input fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef process fill:#ffffcc,stroke:#333,stroke-width:2px
    classDef output fill:#ccccff,stroke:#333,stroke-width:2px
    
    class A,B input
    class C,D,E,C1,C2,C3,D1,D2,E1,E2 process
    class F,G output
```

---

## UI 系统

### UI 结构

```mermaid
graph TD
    A[UI Control] --> B[Panel]
    B --> C[VBoxContainer]
    B --> D[HBoxContainer]
    
    C --> C1[RichTextLabel<br/>Chat Log]
    
    D --> D1[LineEdit<br/>Text Input]
    D --> D2[Button<br/>Send]
    D --> D3[Button<br/>Reconnect]
    
    E[UIController Script] --> B
    E --> F[WebSocket Client]
    E --> G[Message Handling]
    
    F --> F1[user_input 发送]
    F --> F2[chat 接收]
    F --> F3[status_update 接收]
    
    G --> G1[显示聊天消息]
    G --> G2[更新连接状态]
    
    classDef ui fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef script fill:#ffffcc,stroke:#333,stroke-width:2px
    
    class A,B,C,C1,D,D1,D2,D3 ui
    class E,F,G,F1,F2,F3,G1,G2 script
```

### UI 功能

1. **聊天日志显示**
   - 用户输入（蓝色）
   - 萌宠回复（绿色）
   - 系统消息（灰色/黄色）

2. **文本输入**
   - LineEdit 输入框
   - Enter 发送
   - 发送后自动清空焦点

3. **连接状态**
   - 显示连接状态
   - 重连按钮

---

## 数据流与状态管理

### 数据流向图

```mermaid
graph LR
    subgraph "客户端传感器 Sensor"
        A1[用户输入<br/>WASD]
        A2[鼠标点击/拖拽]
        A3[物理状态<br/>position, velocity]
    end
    
    subgraph "服务端决策"
        B1[Blackboard<br/>Sensor Data]
        B2[Behavior Tree<br/>Decision]
        B3[Blackboard<br/>Actuator Output]
    end
    
    subgraph "客户端执行器 Actuator"
        C1[动作指令<br/>JUMP/WAVE/DANCE]
        C2[状态更新<br/>energy/boredom]
        C3[移动指令<br/>move_to]
    end
    
    A1 -->|state_sync| B1
    A2 -->|interaction| B1
    A3 -->|state_sync| B1
    
    B1 --> B2
    B2 --> B3
    
    B3 -->|bt_output| C1
    B3 -->|status_update| C2
    B3 -->|move_to| C3
    
    C1 --> D1[AnimationTree]
    C2 --> D2[BlendTree Parameters]
    C3 --> D3[Physics Movement]
    
    classDef sensor fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef server fill:#ffcccc,stroke:#333,stroke-width:2px
    classDef actuator fill:#ccccff,stroke:#333,stroke-width:2px
    classDef system fill:#ffffcc,stroke:#333,stroke-width:2px
    
    class A1,A2,A3 sensor
    class B1,B2,B3 server
    class C1,C2,C3 actuator
    class D1,D2,D3 system
```

### 状态管理架构

```mermaid
graph TD
    A[PetController] --> B[本地状态]
    A --> C[服务端状态]
    
    B --> B1[current_anim_state<br/>AnimState枚举]
    B --> B2[is_dragging<br/>Boolean]
    B --> B3[target_position<br/>Vector3]
    B --> B4[current_action_state<br/>Dictionary]
    
    C --> C1[actionState<br/>从bt_output]
    C --> C2[energy/boredom<br/>从status_update]
    C --> C3[move_target<br/>从move_to]
    
    B1 --> D[AnimationTree]
    B4 --> D
    C1 --> D
    C2 --> D
    
    B3 --> E[Physics]
    C3 --> E
    
    classDef local fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef remote fill:#ffcccc,stroke:#333,stroke-width:2px
    classDef system fill:#ccccff,stroke:#333,stroke-width:2px
    
    class B,B1,B2,B3,B4 local
    class C,C1,C2,C3 remote
    class D,E system
```

### 输入输出隔离

```mermaid
graph LR
    subgraph "输入 Input - Sensor"
        A1[is_moving_locally]
        A2[is_jump_pressed]
        A3[is_dragging]
        A4[position]
    end
    
    subgraph "输出 Output - Actuator"
        B1[bt_output_action]
        B2[bt_output_position]
        B3[status_update]
    end
    
    A1 -->|上报| C[WebSocket]
    A2 -->|上报| C
    A3 -->|上报| C
    A4 -->|上报| C
    
    C -->|下发| B1
    C -->|下发| B2
    C -->|下发| B3
    
    classDef input fill:#ccffcc,stroke:#333,stroke-width:2px
    classDef output fill:#ffcccc,stroke:#333,stroke-width:2px
    classDef comm fill:#ccccff,stroke:#333,stroke-width:2px
    
    class A1,A2,A3,A4 input
    class B1,B2,B3 output
    class C comm
```

---

## 关键流程时序图

### 1. 用户键盘输入移动流程

```mermaid
sequenceDiagram
    participant U as User
    participant PC as PetController
    participant AT as AnimationTree
    participant WS as WebSocket
    participant S as Server
    
    U->>PC: 按下 W 键
    PC->>PC: 检测输入<br/>input_dir.length() > 0.1
    PC->>AT: 设置参数<br/>locomotion/blend_position = 0.3
    AT->>AT: 混合动画<br/>walk
    PC->>PC: 更新 velocity
    PC->>PC: move_and_slide()
    Note over PC: 本地即时响应<br/>零延迟
    
    PC->>WS: state_sync<br/>is_moving_locally: true
    WS->>S: 发送状态
    
    S->>S: 读取 Sensor<br/>isMovingLocally = true
    S->>S: Behavior Tree<br/>User Control Observer
    S->>S: 决策: 不输出指令<br/>让路给用户
    
    Note over S,PC: 服务端不发送<br/>WALK 指令
```

### 2. 服务端动作指令流程

```mermaid
sequenceDiagram
    participant U as User
    participant UI as UI System
    participant WS as WebSocket
    participant S as Server
    participant PC as PetController
    participant AT as AnimationTree
    
    U->>UI: 输入文字<br/>"跳个舞吧"
    UI->>WS: user_input<br/>{"text": "跳个舞吧"}
    WS->>S: 发送消息
    
    S->>S: LLM 解析意图
    S->>S: Behavior Tree<br/>决策
    S->>S: 生成动作序列<br/>JUMP
    
    S->>WS: bt_output<br/>{"actionState": {<br/>  "name": "JUMP",<br/>  "priority": 50,<br/>  "duration": 1000<br/>}}
    WS->>PC: 接收消息
    
    PC->>PC: _apply_action_state()
    PC->>PC: 优先级检查
    PC->>AT: 设置参数<br/>jump_blend/blend_amount = 1.0
    AT->>AT: 播放 jump 动画
    
    PC->>PC: 设置 action_lock_time
    PC->>PC: 动画完成后清除<br/>jump_blend/blend_amount = 0.0
```

### 3. 鼠标拖拽交互流程

```mermaid
sequenceDiagram
    participant U as User
    participant PC as PetController
    participant WS as WebSocket
    participant S as Server
    participant AT as AnimationTree
    
    U->>PC: 鼠标左键按下
    PC->>PC: 记录点击位置
    
    U->>PC: 鼠标移动<br/>超过阈值
    PC->>PC: is_dragging = true
    PC->>WS: interaction<br/>{"action": "drag_start"}
    WS->>S: 发送消息
    
    S->>S: 更新 Blackboard<br/>isDragging = true
    S->>S: Behavior Tree<br/>拖拽节点触发
    
    loop 拖拽过程中
        U->>PC: 鼠标移动
        PC->>PC: 计算目标位置<br/>raycast to mouse
        PC->>PC: 直接设置位置<br/>global_position = target
        PC->>AT: 保持当前动画
        PC->>WS: state_sync<br/>is_dragging: true
    end
    
    U->>PC: 鼠标左键释放
    PC->>PC: is_dragging = false
    PC->>WS: interaction<br/>{"action": "drag_end"}
    WS->>S: 发送消息
    
    S->>S: 更新 Blackboard<br/>isDragging = false
```

### 4. 状态更新流程

```mermaid
sequenceDiagram
    participant S as Server
    participant WS as WebSocket
    participant PC as PetController
    participant AT as AnimationTree
    
    S->>S: 每2秒更新<br/>energy, boredom
    S->>WS: status_update<br/>{"energy": 75, "boredom": 25}
    WS->>PC: 接收消息
    
    PC->>PC: _on_ws_message<br/>("status_update", data)
    PC->>PC: 归一化数值<br/>energy_normalized = 75/100.0
    PC->>AT: 设置参数<br/>energy_blend/blend_position = 0.75
    AT->>AT: 混合动画<br/>根据能量值调整
    
    Note over AT: 如果实现了能量维度<br/>会自动混合 tired/energetic
```

### 5. 完整交互循环

```mermaid
sequenceDiagram
    participant U as User
    participant PC as PetController
    participant AT as AnimationTree
    participant WS as WebSocket
    participant S as Server
    
    Note over U,S: 初始化阶段
    PC->>WS: connect()
    WS->>S: WebSocket Connection
    PC->>WS: handshake
    WS->>S: 握手消息
    
    Note over U,S: 运行循环
    loop 每帧
        U->>PC: 键盘/鼠标输入
        PC->>AT: 更新动画参数
        PC->>PC: 物理更新
        PC->>WS: state_sync<br/>每100ms
        WS->>S: 状态同步
        
        S->>S: Behavior Tree Tick<br/>每100ms
        alt 有动作指令
            S->>WS: bt_output
            WS->>PC: 动作指令
            PC->>AT: 应用动作
        else 有状态更新
            S->>WS: status_update
            WS->>PC: 状态更新
            PC->>AT: 更新参数
        end
    end
```

---

## 总结

### 核心特性

1. **参数驱动动画**：BlendTree 实现平滑自然的动画混合
2. **输入输出隔离**：传感器与执行器分离，避免冲突
3. **基础移动本地控制**：零延迟的用户体验
4. **特殊动作服务端决策**：AI 驱动的智能行为
5. **马尔可夫决策响应**：无历史依赖的即时响应

### 技术亮点

- **BlendTree 动画系统**：参数驱动，平滑混合，多维扩展
- **WebSocket 双向通信**：实时同步，事件驱动
- **物理引擎集成**：真实的物理交互体验
- **相机系统**：流畅的第三人称视角控制
- **模块化设计**：清晰的职责划分，易于维护

### 扩展方向

1. **动画维度扩展**：能量、情绪等维度的混合
2. **程序化动画**：更多代码驱动的动画效果
3. **特效系统**：粒子效果、音效等增强表现
4. **多人支持**：多客户端同步（未来规划）

---

**文档结束**