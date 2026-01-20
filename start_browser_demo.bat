@echo off
echo ========================================
echo   🐧 Godot Virtual Browser Demo
echo ========================================
echo.

echo 📋 检查环境...
where node >nul 2>nul
if %errorlevel% neq 0 (
    echo ❌ Node.js 未安装，请先安装 Node.js 16+
    pause
    exit /b 1
)

where chrome >nul 2>nul
if %errorlevel% neq 0 (
    echo ⚠️  Chrome 浏览器未在 PATH 中找到
    echo    请确保 Chrome 已安装
)

echo ✅ 环境检查完成
echo.

echo 🚀 启动 AGUI 服务器...
start "AGUI Server" cmd /k "npm start"

echo ⏳ 等待服务器启动...
timeout /t 3 /nobreak >nul

echo 🎮 启动 Godot...
echo    请在 Godot 中打开 scenes/browser_demo.tscn 并运行
echo.
echo 🎯 演示说明:
echo    F1: 切换浏览器模式
echo    F2: 打开 AGUI 界面
echo    F3: 测试命令
echo    ESC: 退出演示
echo.
echo 🌐 浏览器访问:
echo    http://localhost:3000
echo.

pause