@echo off
setlocal
title Comfy Bridge Agent CLI
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-agent.ps1"
if errorlevel 1 (
  echo.
  echo Agent failed to start. See the error above.
  pause
)
endlocal
