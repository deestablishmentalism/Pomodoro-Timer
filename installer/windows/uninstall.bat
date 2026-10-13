@echo off
rem Double-click to uninstall Pomodoro Timer. Uses the installed copy if the repo's copy is missing.
set "SCRIPT=%~dp0uninstall.ps1"
if not exist "%SCRIPT%" set "SCRIPT=%LOCALAPPDATA%\PomodoroTimer\uninstall.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
pause

