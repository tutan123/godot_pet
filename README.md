# Godot 3D 萌宠项目

基于Godot引擎的3D萌宠游戏，完全模仿现有JS前端萌宠的功能。通过WebSocket与服务端通信，实现AI驱动的行为和实时状态同步。

## ✨ 新功能：虚拟浏览器系统

项目现已支持在Godot中嵌入虚拟浏览器，实现AGUI（Advanced GUI）功能！

### 🚀 快速开始

1. **安装依赖**
   ```bash
   npm install
   ```

2. **启动演示**
   ```bash
   # Windows
   start_browser_demo.bat

   # 或者手动启动
   npm start  # 启动AGUI服务器
   # 然后在Godot中运行 scenes/browser_demo.tscn
   ```

3. **访问AGUI界面**
   - 浏览器：http://localhost:3000
   - WebSocket：ws://localhost:8080

### 🎯 AGUI功能

- **🎮 实时控制**：文字指令、动画控制
- **📊 状态监控**：能量、无聊度、当前动作
- **💬 对话界面**：AI对话记录
- **🖱️ 3D交互**：在Godot场景中直接操作浏览器

## 📁 项目结构

```
godot-pet/
├── docs/                    # 文档
│   ├── 虚拟浏览器系统设计方案.md
│   ├── 虚拟浏览器系统使用指南.md
│   └── agui_interface.html  # AGUI界面
├── scenes/                  # Godot场景
│   ├── main.tscn           # 主场景
│   └── browser_demo.tscn   # 浏览器演示
├── scripts/                 # GDScript脚本
│   ├── browser_manager.gd          # 浏览器管理器
│   ├── virtual_browser_3d.gd       # 3D浏览器组件
│   ├── browser_input_manager.gd    # 输入管理
│   ├── browser_process_manager.gd  # 进程管理
│   ├── agui_server.js             # Node.js服务器
│   └── websocket_client.gd         # WebSocket客户端
├── assets/                  # 资源文件
└── package.json            # Node.js配置
```

## 🛠️ 技术栈

- **游戏引擎**: Godot 4.2+
- **3D渲染**: Godot Forward+ / Vulkan
- **通信**: WebSocket (自定义协议)
- **界面**: HTML5 + CSS3 + JavaScript
- **服务器**: Node.js + Express + WS

## 🎮 操作说明

### 基本控制
- **鼠标拖拽**: 拖动萌宠移动
- **键盘输入**: WASD移动，空格跳跃
- **文字指令**: 输入框发送AI指令

### 浏览器演示 (F1-F3)
- **F1**: 切换浏览器显示模式
- **F2**: 打开AGUI界面
- **F3**: 执行测试命令
- **ESC**: 退出演示

## 🔧 开发设置

### Godot开发
1. 下载 [Godot 4.2+](https://godotengine.org/)
2. 打开 `project.godot`
3. 运行主场景或浏览器演示场景

### 服务器开发
```bash
# 安装依赖
npm install

# 启动服务器
npm start

# 开发模式（自动重启）
npm run dev
```

## 📚 文档

- [虚拟浏览器系统设计方案](docs/虚拟浏览器系统设计方案.md)
- [虚拟浏览器系统使用指南](docs/虚拟浏览器系统使用指南.md)
- [Godot客户端架构文档](docs/architecture.md)
- [AGUI界面源码](docs/agui_interface.html)

## 🤝 贡献

欢迎提交Issue和Pull Request！

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🙏 致谢

- Three.js编辑器项目提供的虚拟浏览器灵感
- Godot社区的优秀文档和支持
- 开源Web技术栈的支持