@echo off
setlocal
title SIH PS 26126 - Autonomous UGV Navigation Prototype
cd /d "%~dp0"
echo ========================================================
echo SIH PS 26126: Vision Based Autonomous Navigation UGV
echo ========================================================
echo Launching prototype with Godot 4.x Compatibility Renderer...
echo.

if exist "%~dp0godot.exe" (
    "%~dp0godot.exe"
) else (
    "C:\Users\Sanjeet\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
)

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Godot exited with error code %ERRORLEVEL%.
    pause
)
