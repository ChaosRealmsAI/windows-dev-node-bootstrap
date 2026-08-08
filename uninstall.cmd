@echo off
REM Purpose: Remove only access and state owned by Windows Dev Node Bootstrap.
REM Usage: Double-click uninstall.cmd or run .\uninstall.cmd from PowerShell.
REM Notes: OpenSSH itself is preserved to avoid breaking unrelated users.

setlocal
set "WINDOWS_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "WINDOWS_POWERSHELL=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
set "WINDOWS_DEV_NODE_ENTRY=%~f0"

fltmc >nul 2>&1
if errorlevel 1 (
  "%WINDOWS_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:WINDOWS_DEV_NODE_ENTRY -Verb RunAs"
  exit /b
)

"%WINDOWS_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\Uninstall-WindowsDevNode.ps1"
set "WINDOWS_DEV_NODE_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %WINDOWS_DEV_NODE_EXIT%
