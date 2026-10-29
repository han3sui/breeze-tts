@echo off
title Breeze TTS Intel
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1"
echo.
echo 服务已停止。按任意键关闭窗口。
pause
