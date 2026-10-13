@echo off
rem Double-click to install Pomodoro Timer (bypasses the PowerShell execution policy for this script only)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause

