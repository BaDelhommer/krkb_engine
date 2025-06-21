@echo off

set OUT_DIR=build\debug

if not exist %OUT_DIR% mkdir %OUT_DIR%

odin run win32_platform.odin -file -out:%OUT_DIR%\game_debug.exe -strict-style -vet -debug

echo "Debug build in %OUT_DIR%"
