const express = require('express');
const WebSocket = require('ws');
const path = require('path');
const fs = require('fs');

class AGUIServer {
    constructor() {
        this.app = express();
        this.port = 3000;
        this.wss = null;
        this.godotClients = new Map(); // WebSocket连接到Godot客户端的映射
        this.browserClients = new Map(); // WebSocket连接到浏览器客户端的映射

        this.init();
    }

    init() {
        this.setupExpress();
        this.setupWebSocket();
        this.startServer();
    }

    setupExpress() {
        // 提供静态文件服务
        this.app.use(express.static(path.join(__dirname, '../docs')));

        // 主页面路由
        this.app.get('/', (req, res) => {
            const htmlPath = path.join(__dirname, '../docs/agui_interface.html');
            if (fs.existsSync(htmlPath)) {
                res.sendFile(htmlPath);
            } else {
                res.send(`
                    <!DOCTYPE html>
                    <html>
                    <head>
                        <title>AGUI Server</title>
                        <style>
                            body { font-family: Arial, sans-serif; margin: 40px; }
                            .status { padding: 20px; background: #f0f0f0; border-radius: 8px; }
                        </style>
                    </head>
                    <body>
                        <h1>🐧 AGUI Server</h1>
                        <div class="status">
                            <h2>Server Status: Running</h2>
                            <p>WebSocket Port: 8080</p>
                            <p>HTTP Port: ${this.port}</p>
                            <p>Godot Clients: <span id="godot-count">0</span></p>
                            <p>Browser Clients: <span id="browser-count">0</span></p>
                        </div>
                        <script>
                            // 简单的状态更新（实际项目中可以通过WebSocket获取）
                            setInterval(() => {
                                fetch('/status')
                                    .then(r => r.json())
                                    .then(data => {
                                        document.getElementById('godot-count').textContent = data.godotClients;
                                        document.getElementById('browser-count').textContent = data.browserClients;
                                    })
                                    .catch(() => {});
                            }, 1000);
                        </script>
                    </body>
                    </html>
                `);
            }
        });

        // 状态查询接口
        this.app.get('/status', (req, res) => {
            res.json({
                godotClients: this.godotClients.size,
                browserClients: this.browserClients.size,
                uptime: process.uptime(),
                timestamp: Date.now()
            });
        });

        // 截图上传接口（用于浏览器内容传输）
        this.app.post('/screenshot', express.raw({ type: 'application/octet-stream', limit: '10mb' }), (req, res) => {
            // 转发截图数据到Godot客户端
            this.broadcastToGodot('browser_screenshot', {
                image_data: req.body.toString('base64'),
                format: 'png',
                timestamp: Date.now()
            });
            res.sendStatus(200);
        });
    }

    setupWebSocket() {
        this.wss = new WebSocket.Server({ port: 8080 });
        console.log('🌐 WebSocket server started on port 8080');

        this.wss.on('connection', (ws, req) => {
            console.log('🔗 New WebSocket connection from:', req.socket.remoteAddress);

            ws.on('message', (data) => {
                this.handleMessage(ws, data);
            });

            ws.on('close', () => {
                this.handleDisconnect(ws);
            });

            ws.on('error', (error) => {
                console.error('WebSocket error:', error);
                this.handleDisconnect(ws);
            });

            // 发送欢迎消息
            this.sendMessage(ws, 'welcome', {
                message: 'Connected to AGUI Server',
                timestamp: Date.now()
            });
        });
    }

    handleMessage(ws, data) {
        try {
            const message = JSON.parse(data.toString());
            const { type, data: messageData, timestamp } = message;

            console.log(`📨 Received message: ${type}`, messageData);

            switch (type) {
                case 'handshake':
                    this.handleHandshake(ws, messageData);
                    break;

                case 'agui_command':
                    this.handleAGUICommand(ws, messageData);
                    break;

                case 'browser_event':
                    this.handleBrowserEvent(ws, messageData);
                    break;

                case 'browser_control':
                    this.handleBrowserControl(ws, messageData);
                    break;

                case 'browser_ready':
                    this.handleBrowserReady(ws, messageData);
                    break;

                default:
                    console.log('Unknown message type:', type);
            }
        } catch (error) {
            console.error('Failed to parse message:', error);
            this.sendMessage(ws, 'error', { message: 'Invalid message format' });
        }
    }

    handleHandshake(ws, data) {
        const clientType = data.client_type;

        if (clientType === 'godot_robot') {
            this.godotClients.set(ws, {
                type: 'godot',
                connected_at: Date.now(),
                ...data
            });
            console.log('🤖 Godot client connected');
            this.broadcastToBrowsers('godot_connected', { timestamp: Date.now() });

        } else if (clientType === 'agui_browser') {
            this.browserClients.set(ws, {
                type: 'browser',
                connected_at: Date.now(),
                ...data
            });
            console.log('🌐 Browser client connected');
            this.broadcastToGodot('browser_connected', { timestamp: Date.now() });
        }

        this.sendMessage(ws, 'handshake_ack', {
            success: true,
            client_type: clientType,
            timestamp: Date.now()
        });
    }

    handleAGUICommand(ws, data) {
        const { command, params } = data;
        console.log('🎮 AGUI Command:', command, params);

        // 转发命令到Godot客户端
        this.broadcastToGodot('agui_command', {
            command: command,
            params: params || {},
            timestamp: Date.now()
        });

        // 发送确认响应
        this.sendMessage(ws, 'command_ack', {
            command: command,
            success: true,
            timestamp: Date.now()
        });
    }

    handleBrowserEvent(ws, data) {
        // 转发浏览器事件到Godot
        this.broadcastToGodot('browser_event', {
            ...data,
            timestamp: Date.now()
        });
    }

    handleBrowserControl(ws, data) {
        // 处理Godot发来的浏览器控制命令
        console.log('🎛️ Browser control:', data);

        // 这里可以实现实际的浏览器控制逻辑
        // 例如：通过Chrome DevTools Protocol控制浏览器
        this.sendMessage(ws, 'browser_response', {
            command_id: data.command_id || 'unknown',
            success: true,
            result: { message: 'Command processed' }
        });
    }

    handleBrowserReady(ws, data) {
        console.log('🖥️ Browser ready:', data);
        // 浏览器初始化完成，可以开始发送状态同步
        this.sendMessage(ws, 'browser_init_complete', {
            timestamp: Date.now()
        });
    }

    handleDisconnect(ws) {
        // 清理断开的连接
        if (this.godotClients.has(ws)) {
            this.godotClients.delete(ws);
            console.log('🤖 Godot client disconnected');
            this.broadcastToBrowsers('godot_disconnected', { timestamp: Date.now() });
        }

        if (this.browserClients.has(ws)) {
            this.browserClients.delete(ws);
            console.log('🌐 Browser client disconnected');
            this.broadcastToGodot('browser_disconnected', { timestamp: Date.now() });
        }
    }

    broadcastToGodot(type, data) {
        this.broadcastToClients(this.godotClients, type, data);
    }

    broadcastToBrowsers(type, data) {
        this.broadcastToClients(this.browserClients, type, data);
    }

    broadcastToClients(clientMap, type, data) {
        const message = {
            type: type,
            timestamp: Date.now(),
            data: data
        };

        for (const [ws] of clientMap) {
            if (ws.readyState === WebSocket.OPEN) {
                ws.send(JSON.stringify(message));
            }
        }
    }

    sendMessage(ws, type, data) {
        if (ws.readyState === WebSocket.OPEN) {
            const message = {
                type: type,
                timestamp: Date.now(),
                data: data
            };
            ws.send(JSON.stringify(message));
        }
    }

    // 公共方法：发送消息到所有Godot客户端
    sendToGodot(type, data) {
        this.broadcastToGodot(type, data);
    }

    // 公共方法：发送消息到所有浏览器客户端
    sendToBrowsers(type, data) {
        this.broadcastToBrowsers(type, data);
    }

    // 公共方法：更新宠物状态（从Godot同步到浏览器）
    updatePetStatus(status) {
        this.sendToBrowsers('pet_status', status);
    }

    // 公共方法：添加聊天消息
    addChatMessage(role, content) {
        this.sendToBrowsers('chat_message', {
            role: role,
            content: content,
            timestamp: Date.now()
        });
    }

    startServer() {
        this.app.listen(this.port, () => {
            console.log(`🚀 AGUI Server running on:`);
            console.log(`   HTTP: http://localhost:${this.port}`);
            console.log(`   WebSocket: ws://localhost:8080`);
            console.log(`   AGUI Interface: http://localhost:${this.port}/`);
        });
    }

    // 优雅关闭
    shutdown() {
        console.log('🛑 Shutting down AGUI Server...');

        if (this.wss) {
            this.wss.close();
        }

        process.exit(0);
    }
}

// 创建服务器实例
const server = new AGUIServer();

// 导出服务器实例供其他模块使用
module.exports = server;

// 处理进程信号
process.on('SIGINT', () => server.shutdown());
process.on('SIGTERM', () => server.shutdown());