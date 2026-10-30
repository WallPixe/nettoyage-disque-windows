@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0NettoyageDisque.ps1" %*
echo.
pause
