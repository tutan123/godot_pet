# 动作逻辑职责划分：本地物理混合 vs 服务端马尔可夫决策

## 概述

在本项目中，我们采用了 **"本地传感器上报 + 服务端 AI 决策（马尔可夫性）+ 本地参数化混合表现"** 的现代游戏架构。

### 架构全景图

```mermaid
graph TB
    subgraph User["用户层"]
        Input[WASD/鼠标/语音输入]
    end
    
    subgraph Client["Godot 客户端 (表现层)"]
        Physics[物理引擎<br/>60fps 实时]
        BlendTree[AnimationTree<br/>BlendTree 混合]
        StateSync[状态同步器]
        Anim[角色动画表现]
    end
    
    subgraph Network["通信层 (WebSocket)"]
        WS1[state_sync<br/>传感器数据]
        WS2[bt_output<br/>动作指令]
    end
    
    subgraph Server["JS 服务端 (决策层)"]
        Blackboard[Blackboard 黑板]
        BehaviorTree[RobotBT 行为树<br/>马尔可夫决策]
        LLM[LLM 推理引擎]
        ActionOut[动作输出]
    end
    
    Input --> Physics
    Physics --> BlendTree
    Physics --> StateSync
    BlendTree --> Anim
    StateSync --> WS1
    WS1 --> Blackboard
    Blackboard --> BehaviorTree
    BehaviorTree --> LLM
    LLM --> ActionOut
    ActionOut --> WS2
    WS2 --> BlendTree
    
    style Client fill:#e1f5ff
    style Server fill:#fff4e1
    style Network fill:#f0f0f0
    style User fill:#fff9c4
```

## 1. 职责划分核心原则 (Markov Decision Process)

### 1.1 三层架构

| 层次 | 归属 | 核心技术 | 职责描述 (马尔可夫语义) |
| :--- | :--- | :--- | :--- |
| **表现层 (Actuators)** | Godot 客户端 | **BlendTree** (AnimationTree) | **状态响应器**：根据当前的混合参数（速度、动作权重）实时呈现姿态。 |
| **决策层 (Brain)** | JS 服务端 | **行为树** (Markov BT) | **状态转移器**：每帧观察传感器数据，决定下一刻的"意图（Actuator）"。 |
| **传感器层 (Sensors)** | Godot 客户端 | 物理引擎 + 输入检测 | **环境上报器**：将物理事实（我在动、我在跳）同步到黑板。 |

### 1.2 数据流向

```mermaid
graph LR
    subgraph Sensors["传感器层 (Sensors)"]
        S1[用户输入<br/>WASD/Space/鼠标]
        S2[物理状态<br/>position/velocity]
        S3[碰撞检测<br/>lastCollision]
    end
    
    subgraph Decision["决策层 (Brain)"]
        BB[Blackboard<br/>状态存储]
        BT[BehaviorTree<br/>马尔可夫决策]
        Intent[意图生成<br/>bt_output_action]
    end
    
    subgraph Performance["表现层 (Actuators)"]
        Blend[BlendTree<br/>参数混合]
        Anim[动画播放<br/>60fps]
    end
    
    S1 -->|state_sync| BB
    S2 -->|state_sync| BB
    S3 -->|interaction| BB
    BB --> BT
    BT --> Intent
    Intent -->|bt_output| Blend
    Blend --> Anim
    
    style Sensors fill:#c8e6c9
    style Decision fill:#fff9c4
    style Performance fill:#ffccbc
```

### 1.3 关键特性

**马尔可夫性质 (Markov Property)**：
- 行为树的每一帧决策**仅依赖于黑板上当前的传感器数据**
- 不需要记住"上一秒我发了什么指令"
- 每一帧都根据当前环境重新计算意图

**输入输出隔离 (Input/Output Separation)**：
- 传感器数据 (Sensors)：`isMovingLocally`, `isJumpPressed` 等物理事实
- 执行器数据 (Actuators)：`bt_output_action` 等 AI 意图
- 两者完全解耦，避免冲突

---

## 2. 为什么本地使用"BlendTree"？

我们不再使用简单的"播放"逻辑，而是使用 **BlendTree (混合树)**：

### 2.1 BlendTree 的优势

1.  **参数化驱动**：通过设置 `blend_position` 等参数，动作不再是"硬切换"，而是"无缝滑入"。
2.  **多维混合**：支持在走路的同时进行跳跃（Overlay），或者叠加表情。
3.  **零延迟响应**：本地物理输入（WASD）直接修改混合参数，不经过服务器往返，手感最顺滑。

### 2.2 BlendTree 结构

```mermaid
graph TD
    subgraph BlendTree["AnimationTree (BlendTree)"]
        Root[Root Node]
        Locomotion[Locomotion BlendTree<br/>Idle/Walk/Run]
        JumpOverlay[Jump Blend<br/>Overlay Layer]
        BaseAnim[Base Animation<br/>Idle/Walk/Run]
        JumpAnim[Jump Animation]
        
        Root --> Locomotion
        Locomotion --> BaseAnim
        Root --> JumpOverlay
        JumpOverlay --> JumpAnim
    end
    
    Params[混合参数<br/>blend_position: 0.0-1.0<br/>jump_blend: 0.0-1.0]
    Params --> Locomotion
    Params --> JumpOverlay
    
    style BlendTree fill:#e1f5ff
    style Params fill:#fff9c4
```

### 2.3 参数映射

| 动作状态 | blend_position | jump_blend | 说明 |
|:--------|:--------------|:-----------|:-----|
| IDLE | 0.0 | 0.0 | 待机状态 |
| WALK | 0.5 | 0.0 | 行走状态 |
| RUN | 1.0 | 0.0 | 跑步状态 |
| JUMP | 当前值 | 1.0 | 跳跃覆盖层 |

### 2.4 使用示例

```gdscript
# Godot 客户端代码示例
func _apply_blendtree_state(state: AnimState) -> void:
    match state:
        AnimState.IDLE:
            animation_tree.set("parameters/locomotion/blend_position", 0.0)
            animation_tree.set("parameters/jump_blend/blend_amount", 0.0)
        AnimState.WALK:
            animation_tree.set("parameters/locomotion/blend_position", 0.5)
            animation_tree.set("parameters/jump_blend/blend_amount", 0.0)
        AnimState.RUN:
            animation_tree.set("parameters/locomotion/blend_position", 1.0)
            animation_tree.set("parameters/jump_blend/blend_amount", 0.0)
        AnimState.JUMP:
            animation_tree.set("parameters/jump_blend/blend_amount", 1.0)
```

---

## 3. 为什么服务端是"马尔可夫决策"行为树？

服务端的行为树遵循马尔可夫性质，决策仅依赖于当前黑板状态：

### 3.1 马尔可夫决策特性

1.  **输入输出隔离**：参考 `pointerPosition` 模式，我们将客户端同步来的物理状态（Sensor）与 AI 发出的指令（Actuator）完全解耦。
2.  **AI 让路决策 (User Observer)**：行为树中包含一个显式的优先级分支。当观察到用户在操作时，AI 决策为"保持静默"，主动让出控制权。
3.  **决策一致性**：无论是用户操作还是 LLM 指令，行为树都在每一帧根据全局优先级（碰撞 > 指令 > 用户 > 闲置）进行裁决。

### 3.2 行为树决策流程

```mermaid
graph TD
    Start[行为树 Tick 100ms]
    Update[更新 Blackboard<br/>传感器数据]
    Priority[Priority 节点<br/>优先级裁决]
    
    subgraph HighPriority["高优先级 (100+)"]
        Drag[拖拽交互<br/>isDragging]
        Collision[碰撞反应<br/>lastCollision]
    end
    
    subgraph MediumPriority["中优先级 (50)"]
        LLM[LLM 指令<br/>ExecuteActionSequence]
    end
    
    subgraph LowPriority["低优先级 (10)"]
        User[用户操作观察<br/>User Control Observer]
        Idle[默认 IDLE<br/>PlayAnimationAction]
    end
    
    Start --> Update
    Update --> Priority
    Priority --> Drag
    Priority --> Collision
    Priority --> LLM
    Priority --> User
    Priority --> Idle
    
    Drag -->|isDragging=true| Action1[输出动作/位置]
    Collision -->|lastCollision存在| Action2[输出 BOUNCE]
    LLM -->|pendingActions存在| Action3[执行动作序列]
    User -->|isMovingLocally=true| Yield[让路：不输出]
    Idle -->|无其他动作| Action4[输出 IDLE]
    
    style HighPriority fill:#ffcdd2
    style MediumPriority fill:#fff9c4
    style LowPriority fill:#c8e6c9
```

### 3.3 User Control Observer 机制

```mermaid
graph LR
    Input[用户输入<br/>WASD/Space]
    Client[Godot 客户端<br/>立即响应]
    Sync[state_sync<br/>isMovingLocally=true]
    BB[Blackboard<br/>传感器更新]
    Observer[User Control Observer<br/>检查 isMovingLocally]
    Decision{用户在操作?}
    Yield[让路<br/>不输出 bt_output_action]
    Output[输出动作<br/>bt_output_action]
    
    Input --> Client
    Client --> Sync
    Sync --> BB
    BB --> Observer
    Observer --> Decision
    Decision -->|是| Yield
    Decision -->|否| Output
    
    style Yield fill:#c8e6c9
    style Output fill:#ffccbc
```

### 3.4 代码实现示例

```typescript
// RobotBT.ts - User Control Observer
new BlackboardGuard({
  id: 'guard_user_control_observer',
  title: 'User Control Observer',
  key: (bb: any) => {
    const isMovingLocally = bb.get('isMovingLocally');
    const isDragging = bb.get('isDragging');
    const isJumpPressed = bb.get('isJumpPressed');
    // 如果用户正在本地交互，AI 做出决策：不输出任何指令，让出控制权
    return isMovingLocally || isDragging || isJumpPressed;
  },
  scope: 'global',
  // 这个子节点执行成功但不写入任何 bt_output_action
  child: new class extends Wait {
    tick(tick: any) { return SUCCESS; }
  }({ id: 'node_yield_control', milliseconds: 0 })
})
```

---

## 4. 关键交互流程：以"移动"为例 (输入输出分离模式)

### 4.1 完整流程图

```mermaid
sequenceDiagram
    participant User as 用户
    participant Client as Godot客户端
    participant Blend as BlendTree
    participant WS as WebSocket
    participant Server as BTServer
    participant BB as Blackboard
    participant BT as BehaviorTree
    
    Note over User,BT: 场景：用户按下 W 键移动
    
    User->>Client: 按下 W 键
    Client->>Client: _physics_process()<br/>检测输入
    
    rect rgb(200, 255, 200)
        Note over Client,Blend: 1. 感知 (Sense) - 本地立即响应
        Client->>Blend: 设置 blend_position = 0.5 (Walk)
        Blend->>User: 角色立即开始行走（零延迟）
    end
    
    rect rgb(255, 249, 200)
        Note over Client,BB: 2. 上报 (Report) - 状态同步
        Client->>WS: state_sync {is_moving_locally: true}
        WS->>Server: 接收消息
        Server->>BB: set('isMovingLocally', true)
    end
    
    rect rgb(255, 204, 188)
        Note over BB,BT: 3. 决策 (Decide) - AI 让路
        BB->>BT: 触发 tick()
        BT->>BT: User Control Observer<br/>检测到 isMovingLocally = true
        BT->>BT: 返回 SUCCESS，不写入 bt_output_action
        BT->>BB: bt_output_action 保持为空
    end
    
    rect rgb(200, 255, 200)
        Note over Client,User: 4. 表现 (Perform) - 继续本地控制
        Note over Client: 没有收到冲突指令
        Client->>Client: 继续平滑执行本地物理动画
        Blend->>User: 角色持续行走（无延迟、无冲突）
    end
```

### 4.2 详细步骤说明

1.  **感知 (Sense)**：用户按下 W 键，Godot 设置本地 `WALK` 动画（零延迟），并上报 `is_moving_locally: true` 给服务端。
2.  **决策 (Decide)**：服务端行为树读取黑板传感器。
    *   AI 观察到用户在动。
    *   AI 分支 `User Control Observer` 触发并返回成功。
    *   AI 决策：**不向 `bt_output_action` 写入指令**。
3.  **表现 (Perform)**：Godot 没收到任何冲突指令，继续平滑执行本地物理动画。

### 4.3 与其他场景对比

#### 场景 A：用户移动中，LLM 指令来了

```mermaid
sequenceDiagram
    participant User as 用户
    participant Client as Godot客户端
    participant Server as BTServer
    participant BT as BehaviorTree
    
    User->>Client: 按下 W 键（移动中）
    Client->>Server: state_sync {is_moving_locally: true}
    Server->>BT: tick()
    BT->>BT: User Control Observer 让路
    
    User->>Server: 输入 "跳个舞"
    Server->>BT: LLM 调用，pendingActions = ["DANCE"]
    BT->>BT: ExecuteActionSequence 优先级 50
    Note over BT: 优先级高于 User Observer，执行动作
    Server->>Client: bt_output {actionState: {name: "DANCE"}}
    Client->>Client: _apply_action_state()<br/>优先级检查通过
    Client->>User: 角色开始跳舞（叠加在移动上）
```

#### 场景 B：碰撞反应

```mermaid
sequenceDiagram
    participant Client as Godot客户端
    participant Server as BTServer
    participant BT as BehaviorTree
    participant BB as Blackboard
    
    Client->>Client: 检测到碰撞
    Client->>Server: interaction {action: "collision", ...}
    Server->>BB: set('lastCollision', {...})
    BB->>BT: tick()
    BT->>BT: BlackboardGuard 检测到 lastCollision
    BT->>BB: PushPendingAction {actions: ["BOUNCE"]}
    BT->>BT: ExecuteActionSequence 执行 BOUNCE
    Server->>Client: bt_output {actionState: {name: "BOUNCE"}}
    Client->>Client: 播放弹跳动画
```

---

## 5. 职责对比表

| 维度 | 客户端 (BlendTree) | 服务端 (BehaviorTree) |
|:-----|:------------------|:---------------------|
| **层级** | 表现层 (Presentation) | 决策层 (Decision) |
| **职责** | 动画混合、参数过渡 | 意图生成、动作选择 |
| **频率** | 每帧 (60fps) | 每 100ms (10fps) |
| **输入** | 混合参数 (0.0-1.0) | 传感器数据 (Blackboard) |
| **输出** | 动画播放 | 动作意图 (bt_output_action) |
| **延迟** | 零延迟（本地） | 网络延迟（100ms） |
| **决策依据** | 混合参数值 | 马尔可夫决策（当前状态） |
| **冲突处理** | 优先级检查 | 优先级树结构 |

---

## 6. 总结：马尔可夫决策链

### 6.1 核心原则

*   **Godot 客户端**：物理实体的传感器阵列。
*   **JS 服务端**：纯粹的意图生成器（不做人工过滤，只做逻辑转移）。
*   **通信管道**：声明式同步意图。

这种架构确保了：**AI 拥有灵魂（能够根据感知做出复杂转移），用户拥有身体（操作无延迟）**。

### 6.2 架构优势

```mermaid
mindmap
  root((架构优势))
    零延迟
      本地物理响应
      立即动画切换
      流畅用户体验
    智能决策
      LLM 理解意图
      复杂动作序列
      上下文感知
    无冲突
      AI 主动让路
      优先级仲裁
      输入输出隔离
    可扩展
      易于添加新动作
      灵活的行为树
      模块化设计
```
