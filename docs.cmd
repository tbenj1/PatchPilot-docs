@echo off
setlocal
cd /d "%~dp0"

where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File ".\build\Docs.ps1" %*
  exit /b %errorlevel%
)

powershell -NoProfile -ExecutionPolicy Bypass -File ".\build\Docs.ps1" %*
exit /b %errorlevel%
