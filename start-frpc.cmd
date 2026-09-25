@echo off
setlocal
title Comfy Bridge FRP

set "FRPC=%~dp0.tooling\frp\frpc.exe"
set "CONFIG=%~dp0.tooling\frp\frpc.toml"

if not exist "%FRPC%" (
  echo FRP client was not found: %FRPC%
  pause
  exit /b 1
)

if not exist "%CONFIG%" (
  echo FRP configuration was not found: %CONFIG%
  pause
  exit /b 1
)

"%FRPC%" verify -c "%CONFIG%"
if errorlevel 1 (
  echo.
  echo FRP configuration validation failed.
  pause
  exit /b 1
)

echo.
echo Starting FRP tunnel: public port 18188 to local Agent port 8787
echo Keep this window open. Press Ctrl+C or close it to stop the tunnel.
echo.
"%FRPC%" -c "%CONFIG%"

if errorlevel 1 (
  echo.
  echo FRP client stopped with an error. Check .tooling\frp\frpc.log.
  pause
)

endlocal
