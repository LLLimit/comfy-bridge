@echo off
setlocal
title Comfy Bridge Control Center
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-agent-gui.ps1"
if errorlevel 1 (
  echo.
  echo Comfy Bridge Control Center failed to start. See the error above.
  pause
)
endlocal
