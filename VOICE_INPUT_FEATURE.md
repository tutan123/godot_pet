# 语音输入功能说明

## 功能概述

为Godot客户端添加了语音输入功能，包括：
1. 设置页面：可以配置WebSocket服务端地址和ASR服务端地址
2. 语音输入按钮：长按开始录音，松开结束
3. 实时语音识别：通过WebSocket连接到ASR服务进行流式识别

## 新增文件

### 脚本文件
- `scripts/config_manager.gd` - 配置管理，负责保存和加载应用配置
- `scripts/settings_ui.gd` - 设置界面控制器
- `scripts/asr_websocket_client.gd` - ASR服务的WebSocket客户端
- `scripts/audio_recorder.gd` - 音频录制模块

### 场景文件
- `scenes/settings.tscn` - 设置页面场景

## 修改的文件

### 主场景 (`scenes/main.tscn`)
- 添加了 `ConfigManager` 节点
- 添加了 `ASRWebSocketClient` 节点
- 添加了 `AudioRecorder` 节点
- 在UI中添加了 `VoiceButton`（🎤）和 `SettingsButton`（⚙）
- 添加了 `Settings` 场景实例

### UI控制器 (`scripts/ui_controller.gd`)
- 添加了语音输入按钮的事件处理
- 添加了设置按钮的事件处理
- 实现了语音录制和ASR识别结果的接收
- 识别结果自动填入输入框

### WebSocket客户端 (`scripts/websocket_client.gd`)
- 修改为从ConfigManager加载配置

## 使用方法

### 1. 配置服务地址
1. 点击输入框旁边的齿轮按钮（⚙）
2. 在设置页面中配置：
   - **WebSocket 服务端地址**：主服务的WebSocket地址（默认：`ws://localhost:8080`）
   - **ASR 服务端地址**：语音识别服务的WebSocket地址（默认：`ws://localhost:8000/api/v1/realtime`）
3. 点击"保存"按钮保存配置

### 2. 使用语音输入
1. 确保ASR服务已启动（运行 `python start.py` 在 `VOICE/voice_engine` 目录）
2. 在输入框旁边找到麦克风按钮（🎤）
3. **长按**麦克风按钮开始录音
4. 说话时按钮会变红，表示正在录音
5. **松开**按钮结束录音
6. 识别结果会自动填入输入框
7. 可以编辑识别结果或直接点击"Send"发送

## ASR服务配置

ASR服务需要支持以下WebSocket消息格式：

### 客户端发送
```json
// 开始会话
{
  "type": "start",
  "config": {
    "language": "zh",
    "use_itn": true,
    "vad_enabled": true,
    "chunk_size": 600
  }
}

// 发送音频数据（base64编码）
{
  "type": "audio",
  "data": "base64_encoded_audio_data"
}

// 结束会话
{
  "type": "end"
}
```

### 服务端返回
```json
// 会话开始确认
{
  "status": "started",
  "session_id": "session_123"
}

// 识别结果
{
  "status": "result",
  "data": {
    "text": "识别的文本",
    "is_final": false
  }
}

// 会话结束
{
  "status": "ended",
  "final_result": {
    "text": "最终识别的文本"
  }
}
```

## 技术细节

### 音频格式
- 采样率：16kHz
- 声道：单声道
- 位深：16位
- 格式：PCM

### 配置存储
配置保存在 `user://godot_pet_config.cfg`，使用Godot的ConfigFile格式。

### 录音实现
使用Godot的 `AudioEffectRecord` 进行录音，支持实时流式发送音频数据到ASR服务。

## 注意事项

1. 首次使用需要配置ASR服务地址
2. 确保ASR服务已启动并可以访问
3. 录音需要麦克风权限（Godot会自动请求）
4. 如果ASR服务连接失败，会在聊天日志中显示错误信息
5. 长按录音时，按钮会变红表示正在录音

## 故障排除

### ASR服务连接失败
- 检查ASR服务是否已启动
- 检查ASR服务地址是否正确
- 检查防火墙设置

### 录音没有声音
- 检查麦克风权限
- 检查系统音频设置
- 查看Godot控制台的错误信息

### 识别结果不准确
- 确保说话清晰
- 检查环境噪音
- 可以尝试调整ASR服务的配置参数
