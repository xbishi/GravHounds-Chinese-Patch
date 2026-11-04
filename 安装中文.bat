@echo off
chcp 65001 >nul
title GRAVHOUNDS Chinese Patch - Install
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install.ps1" %*
echo.
pause
