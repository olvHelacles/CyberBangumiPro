@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_release.ps1"
if %errorlevel% neq 0 (
    echo.
    echo 构建失败，请检查上方错误信息。
    pause
)
