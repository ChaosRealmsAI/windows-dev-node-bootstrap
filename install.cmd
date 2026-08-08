@echo off
REM Purpose: Elevate once and install or repair the LAN-only Windows development node.
REM Usage: Double-click install.cmd or run .\install.cmd from PowerShell.
REM Notes: The elevated window stays open so the safe pairing report can be copied.

setlocal
set "WINDOWS_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "WINDOWS_POWERSHELL=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
set "WINDOWS_DEV_NODE_ENTRY=%~f0"

fltmc >nul 2>&1
if errorlevel 1 (
  "%WINDOWS_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:WINDOWS_DEV_NODE_ENTRY -Verb RunAs"
  exit /b
)

"%WINDOWS_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\Install-WindowsDevNode.ps1"
set "WINDOWS_DEV_NODE_EXIT=%ERRORLEVEL%"
echo.
if not "%WINDOWS_DEV_NODE_EXIT%"=="0" echo Installation did not reach READY. Copy only the delimited pairing report or the final error line.
pause
exit /b %WINDOWS_DEV_NODE_EXIT%
