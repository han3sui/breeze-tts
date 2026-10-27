@echo off
title Breeze TTS Intel
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1"
echo.
pause
