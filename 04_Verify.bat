@echo off
setlocal
chcp 65001 >nul
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Manage.ps1" -Action Verify %*
set "result=%errorlevel%"
echo.
echo Exit code: %result%
pause
exit /b %result%
