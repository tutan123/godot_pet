class_name StateSynchronizer
extends Node

# 同步配置
@export var sync_interval: float = 0.1  # 100ms
@export var max_sync_queue_size: int = 100
@export var enable_compression: bool = false
@export var enable_delta_sync: bool = true

# 状态数据
var ui_states: Dictionary = {}
var last_synced_states: Dictionary = {}
var sync_queue: Array = []

# 同步计时器
var sync_timer: Timer

# 信号
signal state_synced(panel_id: String, state_data: Dictionary)
signal sync_failed(panel_id: String, error: String)
signal batch_sync_completed(success_count: int, fail_count: int)

func _ready():
    _setup_sync_timer()

func _setup_sync_timer():
    sync_timer = Timer.new()
    sync_timer.wait_time = sync_interval
    sync_timer.autostart = true
    sync_timer.timeout.connect(_process_sync_queue)
    add_child(sync_timer)

# 更新UI状态
func update_ui_state(panel_id: String, state_data: Dictionary):
    ui_states[panel_id] = state_data

    # 添加到同步队列
    sync_queue.append({
        "panel_id": panel_id,
        "state_data": state_data,
        "timestamp": Time.get_unix_time_from_system(),
        "priority": _calculate_sync_priority(state_data)
    })

    # 限制队列大小
    if sync_queue.size() > max_sync_queue_size:
        sync_queue.pop_front()

# 获取UI状态
func get_ui_state(panel_id: String) -> Dictionary:
    return ui_states.get(panel_id, {})

# 获取所有状态
func get_all_states() -> Dictionary:
    return ui_states.duplicate()

# 批量更新状态
func batch_update_states(states: Dictionary):
    for panel_id in states.keys():
        update_ui_state(panel_id, states[panel_id])

# 处理同步队列
func _process_sync_queue():
    if sync_queue.is_empty():
        return

    # 按优先级排序
    sync_queue.sort_custom(func(a, b): return a.priority > b.priority)

    # 批量同步
    var batch_size = min(sync_queue.size(), 10)  # 每次最多同步10个
    var batch = sync_queue.slice(0, batch_size)

    _perform_batch_sync(batch)

# 执行批量同步
func _perform_batch_sync(batch: Array):
    var success_count = 0
    var fail_count = 0

    for item in batch:
        var result = _sync_single_state(item.panel_id, item.state_data)
        if result.success:
            success_count += 1
            state_synced.emit(item.panel_id, item.state_data)
            last_synced_states[item.panel_id] = item.state_data.duplicate()
        else:
            fail_count += 1
            sync_failed.emit(item.panel_id, result.error)

        # 从队列中移除
        sync_queue.erase(item)

    batch_sync_completed.emit(success_count, fail_count)

# 同步单个状态
func _sync_single_state(panel_id: String, state_data: Dictionary) -> Dictionary:
    # 获取WebSocket客户端
    var websocket_client = get_parent().get_node_or_null("WebSocketClient")
    if not websocket_client:
        return {"success": false, "error": "WebSocket client not found"}

    if not websocket_client.is_connected:
        return {"success": false, "error": "WebSocket not connected"}

    # 准备同步数据
    var sync_data = _prepare_sync_data(panel_id, state_data)

    # 发送同步消息
    var message = {
        "type": "ui_state_sync",
        "panel_id": panel_id,
        "state_data": sync_data,
        "timestamp": Time.get_unix_time_from_system()
    }

    var result = websocket_client.send_json(message)
    if result:
        return {"success": true}
    else:
        return {"success": false, "error": "Failed to send message"}

# 准备同步数据
func _prepare_sync_data(panel_id: String, state_data: Dictionary) -> Dictionary:
    var sync_data = state_data.duplicate()

    if enable_delta_sync:
        # 计算增量同步
        var last_state = last_synced_states.get(panel_id, {})
        sync_data = _calculate_delta(last_state, state_data)

    if enable_compression:
        # 压缩数据（这里可以实现简单的压缩逻辑）
        sync_data = _compress_data(sync_data)

    return sync_data

# 计算状态增量
func _calculate_delta(old_state: Dictionary, new_state: Dictionary) -> Dictionary:
    var delta = {}

    # 找出新增或修改的字段
    for key in new_state.keys():
        if not old_state.has(key) or old_state[key] != new_state[key]:
            delta[key] = new_state[key]

    # 标记删除的字段（如果需要）
    for key in old_state.keys():
        if not new_state.has(key):
            delta[key] = null  # 使用null表示删除

    return delta

# 数据压缩（简化实现）
func _compress_data(data: Dictionary) -> Dictionary:
    # 这里可以实现更复杂的压缩逻辑
    # 目前只是移除空值
    var compressed = {}
    for key in data.keys():
        var value = data[key]
        if value != null and value != "":
            compressed[key] = value
    return compressed

# 计算同步优先级
func _calculate_sync_priority(state_data: Dictionary) -> int:
    var priority = 1

    # 根据状态类型设置优先级
    if state_data.has("interaction_type"):
        priority = 10  # 交互事件最高优先级

    if state_data.has("position") or state_data.has("rotation"):
        priority = 5  # 变换事件较高优先级

    if state_data.has("visible"):
        priority = 3  # 可见性变化中等优先级

    return priority

# 接收来自手机的状态更新
func receive_mobile_state_update(panel_id: String, state_data: Dictionary):
    # 更新本地状态
    ui_states[panel_id] = state_data

    # 通知UI渲染器更新
    var ui_renderer = get_parent().get_node_or_null("UIRenderer3D")
    if ui_renderer:
        ui_renderer.update_panel(panel_id, state_data)

# 处理手机发送的状态同步消息
func handle_mobile_sync_message(message: Dictionary):
    var panel_id = message.get("panel_id", "")
    var state_data = message.get("state_data", {})
    var sync_type = message.get("sync_type", "full")

    if panel_id == "":
        return

    match sync_type:
        "full":
            receive_mobile_state_update(panel_id, state_data)
        "delta":
            _apply_delta_update(panel_id, state_data)
        "batch":
            _apply_batch_update(message.get("panels", {}))

# 应用增量更新
func _apply_delta_update(panel_id: String, delta_data: Dictionary):
    var current_state = ui_states.get(panel_id, {})

    for key in delta_data.keys():
        var value = delta_data[key]
        if value == null:
            current_state.erase(key)  # 删除字段
        else:
            current_state[key] = value  # 更新字段

    ui_states[panel_id] = current_state
    receive_mobile_state_update(panel_id, current_state)

# 应用批量更新
func _apply_batch_update(panels_data: Dictionary):
    for panel_id in panels_data.keys():
        var state_data = panels_data[panel_id]
        receive_mobile_state_update(panel_id, state_data)

# 强制全量同步
func force_full_sync(panel_id: String = ""):
    if panel_id == "":
        # 同步所有面板
        for pid in ui_states.keys():
            var result = _sync_single_state(pid, ui_states[pid])
            if result.success:
                last_synced_states[pid] = ui_states[pid].duplicate()
    else:
        # 同步指定面板
        if ui_states.has(panel_id):
            var result = _sync_single_state(panel_id, ui_states[panel_id])
            if result.success:
                last_synced_states[panel_id] = ui_states[panel_id].duplicate()

# 获取同步统计信息
func get_sync_stats() -> Dictionary:
    return {
        "queued_syncs": sync_queue.size(),
        "tracked_panels": ui_states.size(),
        "last_sync_time": sync_timer.time_left if sync_timer else 0.0,
        "compression_enabled": enable_compression,
        "delta_sync_enabled": enable_delta_sync
    }

# 设置同步配置
func set_sync_config(config: Dictionary):
    if config.has("sync_interval"):
        sync_interval = config.sync_interval
        if sync_timer:
            sync_timer.wait_time = sync_interval

    if config.has("max_sync_queue_size"):
        max_sync_queue_size = config.max_sync_queue_size

    if config.has("enable_compression"):
        enable_compression = config.enable_compression

    if config.has("enable_delta_sync"):
        enable_delta_sync = config.enable_delta_sync

# 清除状态数据
func clear_states():
    ui_states.clear()
    last_synced_states.clear()
    sync_queue.clear()

# 暂停同步
func pause_sync():
    if sync_timer:
        sync_timer.stop()

# 恢复同步
func resume_sync():
    if sync_timer:
        sync_timer.start()