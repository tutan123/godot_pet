# EQS 移动工具说明

## 新增的移动工具

现在 LLM 可以直接调用以下移动工具来执行移动操作：

### 1. `move_to` - 通用移动工具

**功能**：将角色移动到指定位置，可以指定坐标或使用 EQS 查询结果。

**参数**：
```json
{
  "targetPos": [10, 0, 10],  // 可选：目标位置 [x, y, z]
  "moveType": "walk"          // 可选：移动类型 "walk" 或 "run"，默认 "walk"
}
```

**使用场景**：
- 如果提供了 `targetPos`，直接移动到该位置
- 如果没有提供 `targetPos`，会自动使用 EQS 查询的结果（`eqs_best_position` 或 `bt_output_position`）

**示例**：
```json
// LLM 调用示例
{
  "function": {
    "name": "move_to",
    "arguments": "{\"targetPos\": [10, 0, 10], \"moveType\": \"walk\"}"
  }
}
```

### 2. `walk_to` - 走到指定位置

**功能**：使用走路动画走到指定位置。

**参数**：
```json
{
  "targetPos": [10, 0, 10]  // 必需：目标位置 [x, y, z]
}
```

**示例**：
```json
{
  "function": {
    "name": "walk_to",
    "arguments": "{\"targetPos\": [10, 0, 10]}"
  }
}
```

### 3. `run_to` - 跑到指定位置

**功能**：使用跑步动画跑到指定位置。

**参数**：
```json
{
  "targetPos": [10, 0, 10]  // 必需：目标位置 [x, y, z]
}
```

**示例**：
```json
{
  "function": {
    "name": "run_to",
    "arguments": "{\"targetPos\": [10, 0, 10]}"
  }
}
```

### 4. `move_to_eqs_result` - 移动到 EQS 查询结果

**功能**：移动到 EQS 环境查询的结果位置。需要先调用 `query_environment` 工具。

**参数**：
```json
{
  "moveType": "walk"  // 可选：移动类型 "walk" 或 "run"，默认 "walk"
}
```

**使用流程**：
1. 先调用 `query_environment` 查询最佳位置
2. 然后调用 `move_to_eqs_result` 移动到查询结果

**示例**：
```json
// 第一步：查询位置
{
  "function": {
    "name": "query_environment",
    "arguments": "{\"goal\": \"走到小球那\"}"
  }
}

// 第二步：移动到查询结果
{
  "function": {
    "name": "move_to_eqs_result",
    "arguments": "{\"moveType\": \"walk\"}"
  }
}
```

## 完整工作流程示例

### 场景：用户说"请走到小球那"

**步骤 1**：LLM 调用 EQS 查询工具
```json
{
  "function": {
    "name": "query_environment",
    "arguments": "{\"goal\": \"走到小球那\", \"constraints\": [\"可达\"]}"
  }
}
```

**步骤 2**：EQS 查询完成，结果写入黑板
- `eqs_best_position = [9.5, 0, 9.5]`
- `bt_output_position = [9.5, 0, 9.5]`

**步骤 3**：LLM 调用移动工具（两种方式）

**方式 A**：使用 `move_to`（自动使用 EQS 结果）
```json
{
  "function": {
    "name": "move_to",
    "arguments": "{\"moveType\": \"walk\"}"
  }
}
```

**方式 B**：使用 `move_to_eqs_result`
```json
{
  "function": {
    "name": "move_to_eqs_result",
    "arguments": "{\"moveType\": \"walk\"}"
  }
}
```

**步骤 4**：服务端发送 `move_to` 消息到客户端
```json
{
  "type": "move_to",
  "data": {
    "target": [9.5, 0, 9.5]
  }
}
```

**步骤 5**：客户端执行移动，角色自动走到目标位置

## 工具优先级

`MoveToNode` 获取目标位置的优先级：

1. **参数中的 `targetPos`**（最高优先级）
2. **黑板中的 `targetKey` 指定的位置**
3. **EQS 查询结果**（`eqs_best_position` 或 `bt_output_position`）

## 与现有系统的集成

- ✅ 与 `EQSQueryNode` 完美集成：EQS 查询结果可以直接用于移动
- ✅ 与 `BTServer` 集成：自动发送 `move_to` 消息到客户端
- ✅ 与客户端集成：客户端接收 `move_to` 消息后执行移动

## 测试

运行测试：
```bash
cd AVATAR/q_llm_pet
npm test -- MoveToNode.test.ts
```

测试结果：✅ 6/6 通过
