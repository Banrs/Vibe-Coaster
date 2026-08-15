@echo off
setlocal
rem Launch the Vibe-Coaster viewer. Set GODOT to override the engine binary.
if "%GODOT%"=="" set "GODOT=D:\Games\Godot_v4.7.1-stable_win64.exe"
if not exist "%GODOT%" (
	echo Godot 4.7 not found at "%GODOT%".
	echo Set the GODOT environment variable to your Godot 4.7 binary and re-run.
	exit /b 1
)
"%GODOT%" --path "%~dp0godot" %*
