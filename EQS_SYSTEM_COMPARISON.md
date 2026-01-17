# EQS 系统新旧版本对比分析

## 概述

本文档详细对比分析了 `GAME/godot-pet` (新版本) 和 `GAME/godot-pet-origin/godot_pet` (旧版本) 的EQS（环境查询系统）实现，找出导致查询失败的根本原因，并提供修复方案。

## 主要问题识别

### 🔴 **核心问题：查询流程不完整**

新版本的EQS查询在以下关键环节失败：
1. 消息格式解析问题
2. 上下文构建不完整
3. 导航网格未初始化
4. 信号连接和处理逻辑差异

## 详细对比分析

### 1. 消息处理流程对比

#### 旧版本消息处理流程
```gdscript
// pet_controller.gd
func _on_eqs_query_received(data: Dictionary) -> void:
    var query_id = data.get("query_id", "")
    var config = data.get("config", {})

    if query_id.is_empty() or config.is_empty():
        _log("[EQS] Invalid query request")
        return

    // 构建上下文
    var context = {
        "querier_position": [global_position.x, global_position.y, global_position.z],
        "target_position": null,
        "enemy_positions": []
    }

    // 执行查询
    eqs_adapter.execute_query(query_id, config, context)
```

**特点：**
- 直接处理消息，假设格式为 `{query_id, config, context}`
- 上下文在控制器中构建
- 简单直接，但不够灵活

#### 新版本消息处理流程
```gdscript
// pet_controller.gd
func _on_eqs_query_received(d: Dictionary) -> void:
    // 支持两种格式的兼容处理
    var query_id = d.get("query_id", "")
    var data = d.get("data", {})
    var config = data.get("config", d.get("config", {}))
    var context = data.get("context", {})

    // 智能上下文构建
    if context.is_empty():
        context = {
            "querier_position": [global_position.x, global_position.y, global_position.z],
            ...
        }

    eqs_adapter.execute_query(query_id, config, context)
```

**特点：**
- 支持多种消息格式的兼容性
- 更智能的上下文处理
- 但增加了复杂性，可能导致解析错误

### 2. EQS适配器对比

#### 信号定义差异
```gdscript
// 旧版本
signal eqs_result_ready(query_id: String, results: Array)

// 新版本
signal eqs_result_ready(query_id: String, response: Dictionary)
```

**影响：**
- 信号参数类型不匹配
- 新版本发送完整的response字典，旧版本期望Array
- 需要确保信号连接和处理函数匹配

#### 导航网格设置差异
```gdscript
// 旧版本 - 有导航网格设置
_ready():
    var navmesh_node = get_node_or_null("/root/Main/NavigationRegion3D")
    if navmesh_node:
        eqs_adapter.navmesh = navmesh_node

// 新版本 - 缺少导航网格设置 ❌
_ready():
    // 没有设置导航网格！
```

**影响：**
- Pathfinding测试失败
- 查询结果不准确

### 3. 查询执行流程对比

#### 生成候选点阶段
```gdscript
// 两版本基本相同，但调试信息不同
func _generate_circle(params, context):
    // 解析参数
    var center = _get_pos_from_context(context, "querier_position")
    // 生成圆形分布的点
```

#### 测试评估阶段
```gdscript
// 两版本基本相同
func _evaluate_point(point, tests, context):
    for test_config in tests:
        var score = _run_test(point, test_type, params, context)
        if score < 0: return -1.0  // 过滤掉
        total_score *= score
```

#### 结果发送阶段
```gdscript
// 旧版本发送Array
eqs_result_ready.emit(query_id, results)

// 新版本发送Dictionary
var response = {"query_id": query_id, "results": results, ...}
eqs_result_ready.emit(query_id, response)
```

## 修复方案

### 1. **消息格式兼容性修复** ✅
```gdscript
// 支持多种消息格式
var config = data.get("config", d.get("config", {}))
var context = data.get("context", {})
```

### 2. **导航网格初始化修复** ✅
```gdscript
// 在_ready中设置导航网格
var navmesh_node = get_node_or_null("/root/Main/NavigationRegion3D")
if navmesh_node:
    eqs_adapter.navmesh = navmesh_node
```

### 3. **信号连接一致性修复** ✅
```gdscript
// 确保信号定义和使用一致
signal eqs_result_ready(query_id: String, response: Dictionary)
func _on_eqs_result_ready(query_id: String, response: Dictionary):
```

### 4. **上下文构建完整性修复** ✅
```gdscript
// 确保上下文包含所有必要信息
context = {
    "querier_position": [x, y, z],
    "target_position": target_pos,
    "enemy_positions": enemy_pos
}
```

### 5. **调试信息增强** ✅
```gdscript
// 添加详细的执行过程日志
print("[EQSAdapter] === Starting query %s ===" % query_id)
print("[EQSAdapter] Config: %s" % str(config))
print("[EQSAdapter] Generated %d candidate points" % points.size())
```

### 6. **WebSocket消息路由修复** ✅
```gdscript
// 重新连接WebSocket消息接收信号
if ws_client:
    ws_client.message_received.connect(_on_ws_message)
```

## 完整修复总结

经过详细分析，发现了导致EQS查询失败的**根本原因**：

### 🔴 **核心问题：WebSocket消息路由完全断开**

新版本重构时，意外删除了pet_controller对WebSocket消息的连接，导致：
- 所有机器人控制相关的消息（包括EQS查询）都没有被处理
- 客户端表现为正常连接，但对服务器指令无响应

### ✅ **完整修复方案**

1. **消息路由重建**：重新连接WebSocket信号到pet_controller
2. **消息格式兼容**：支持多种消息格式的解析
3. **上下文完整性**：确保位置信息正确构建
4. **导航网格初始化**：为pathfinding提供必要数据
5. **调试信息完善**：便于问题排查和状态监控
```gdscript
// 添加详细的调试日志
print("[EQSAdapter] === Starting query %s ===" % query_id)
print("[EQSAdapter] Config: %s" % str(config))
print("[EQSAdapter] Generated %d candidate points" % points.size())
```

## 测试验证

运行"飞到舞台上"命令，观察控制台输出：

### 期望的调试输出
```
[EQS] Received query: eqs_xxx
[EQS] Extracted config: {...}
[EQS] Final context: {...}
[EQSAdapter] === Starting query eqs_xxx ===
[EQSAdapter] Generator type: Points_Circle
[EQSAdapter] SUCCESS: Generated 16 candidate points
[EQSAdapter] Query eqs_xxx completed: 5 valid results
[EQS] Sent result for query: eqs_xxx (5 results, 150ms)
```

### 如果仍有问题，检查
1. 导航网格是否正确加载
2. 上下文中的位置信息是否准确
3. 服务端是否能接收到eqs_result消息

## 架构建议

### 保持向后兼容
```gdscript
// 支持旧版本的消息格式
var config = data.get("config", d.get("config", {}))
var context = data.get("context", d.get("context", {}))
```

### 统一调试标准
```gdscript
// 所有EQS相关函数都应有调试输出
print("[EQSAdapter] %s" % message)
```

### 健壮的错误处理
```gdscript
// 防止单个查询失败影响整个系统
if candidate_points.is_empty():
    _send_result(query_id, [], "No candidate points")
    return
```

## 总结

新版本的EQS系统比旧版本更加灵活和完整，但引入了一些兼容性问题。通过上述修复，应该能够恢复EQS查询功能。

关键修复点：
1. ✅ 消息格式兼容性
2. ✅ 导航网格初始化
3. ✅ 上下文构建完整性
4. ✅ 调试信息增强

这些修复确保了EQS系统能够正确处理"飞到舞台上"等查询请求。

## 补充：消息路由修复

经过实际测试发现，还有一个**关键问题**：WebSocket消息路由完全断开。

### 🔴 **核心问题扩展**

**消息路由断开**：新版本删除了pet_controller对WebSocket消息的连接，导致所有机器人控制消息无法被处理。

**修复**：
```gdscript
// 在pet_controller的_ready中重新连接
if ws_client:
    ws_client.message_received.connect(_on_ws_message)

func _on_ws_message(type: String, data: Dictionary) -> void:
    messaging_module.handle_ws_message(type, data, animation_tree)
```

---

**最终更新**：2026年1月17日 - 修复WebSocket消息路由断开问题