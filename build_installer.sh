#!/bin/bash
# build_installer.sh - Generate a self-contained Windows installer .cmd
# Usage: ./build_installer.sh <dll_path> <lua_path> <output_cmd>

set -e

DLL="$1"
LUA="$2"
OUTPUT="$3"

if [ ! -f "$DLL" ] || [ ! -f "$LUA" ]; then
    echo "Usage: $0 <dll_path> <lua_path> <output_cmd>" >&2
    exit 1
fi

DLL_B64=$(base64 -w76 "$DLL")
LUA_B64=$(base64 -w76 "$LUA")

cat > "$OUTPUT" << 'HEADER'
@echo off
setlocal enabledelayedexpansion
title VLScheduler Installer

:: ---------------------------------------------------------------
:: Request admin elevation if not already elevated
:: ---------------------------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b 0
)

echo.
echo  VLScheduler Installer
echo  =====================
echo.

:: ---------------------------------------------------------------
:: Detect VLC installation
:: ---------------------------------------------------------------
set "VLC_DIR="
for %%d in ("%ProgramFiles%\VideoLAN\VLC" "%ProgramFiles(x86)%\VideoLAN\VLC") do (
    if exist "%%~d\vlc.exe" (
        set "VLC_DIR=%%~d"
    )
)
if not defined VLC_DIR (
    echo  [ERROR] VLC not found in Program Files.
    echo  Please install VLC first, then run this installer again.
    echo.
    pause
    exit /b 1
)
echo  Found VLC at: %VLC_DIR%

:: ---------------------------------------------------------------
:: Check if VLC is running
:: ---------------------------------------------------------------
tasklist /FI "IMAGENAME eq vlc.exe" 2>nul | %SystemRoot%\System32\find.exe /i "vlc.exe" >nul
if %errorlevel%==0 (
    echo.
    echo  [WARNING] VLC is currently running.
    echo  Please close VLC before installing.
    echo.
    pause
    exit /b 1
)

:: ---------------------------------------------------------------
:: Extract embedded files
:: ---------------------------------------------------------------
set "TMPDIR=%TEMP%\vlscheduler_install"
mkdir "%TMPDIR%" 2>nul

echo  Extracting files...

:: Use PowerShell to extract base64 sections from this script
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$content = [IO.File]::ReadAllText('%~f0', [Text.Encoding]::ASCII);" ^
  "$dllMatch = [regex]::Match($content, '::DLL_BASE64_START\r?\n([\s\S]*?)::DLL_BASE64_END');" ^
  "$luaMatch = [regex]::Match($content, '::LUA_BASE64_START\r?\n([\s\S]*?)::LUA_BASE64_END');" ^
  "if (-not $dllMatch.Success -or -not $luaMatch.Success) { Write-Error 'Failed to extract data'; exit 1 };" ^
  "$dllB64 = $dllMatch.Groups[1].Value -replace '\s','';" ^
  "$luaB64 = $luaMatch.Groups[1].Value -replace '\s','';" ^
  "[IO.File]::WriteAllBytes('%TMPDIR%\libscheduler_plugin.dll', [Convert]::FromBase64String($dllB64));" ^
  "$luaBytes = [Convert]::FromBase64String($luaB64);" ^
  "$utf8NoBom = New-Object System.Text.UTF8Encoding($false);" ^
  "[IO.File]::WriteAllText('%TMPDIR%\vlscheduler.lua', $utf8NoBom.GetString($luaBytes), $utf8NoBom)"

if %errorlevel% neq 0 (
    echo  [ERROR] Failed to extract files.
    pause
    exit /b 1
)

:: ---------------------------------------------------------------
:: Install plugin
:: ---------------------------------------------------------------
set "PLUGIN_DIR=%VLC_DIR%\plugins\misc"
echo  Installing plugin to: %PLUGIN_DIR%
copy /Y "%TMPDIR%\libscheduler_plugin.dll" "%PLUGIN_DIR%\" >nul
if %errorlevel% neq 0 (
    echo  [ERROR] Failed to copy plugin.
    pause
    exit /b 1
)

:: ---------------------------------------------------------------
:: Install Lua extension
:: ---------------------------------------------------------------
set "EXT_DIR=%APPDATA%\vlc\lua\extensions"
mkdir "%EXT_DIR%" 2>nul
echo  Installing extension to: %EXT_DIR%
copy /Y "%TMPDIR%\vlscheduler.lua" "%EXT_DIR%\" >nul

:: ---------------------------------------------------------------
:: Delete VLC plugin cache to force rescan
:: ---------------------------------------------------------------
del "%VLC_DIR%\plugins\plugins.dat" 2>nul

:: ---------------------------------------------------------------
:: Cleanup
:: ---------------------------------------------------------------
rmdir /S /Q "%TMPDIR%" 2>nul

echo.
echo  =============================================
echo   VLScheduler installed successfully!
echo   Restart VLC to activate the extension.
echo   Go to View ^> VLScheduler ^> Schedule Setup
echo  =============================================
echo.
pause
exit /b 0

HEADER

# Append DLL data
echo "::DLL_BASE64_START" >> "$OUTPUT"
echo "$DLL_B64" >> "$OUTPUT"
echo "::DLL_BASE64_END" >> "$OUTPUT"

# Append Lua data
echo "::LUA_BASE64_START" >> "$OUTPUT"
echo "$LUA_B64" >> "$OUTPUT"
echo "::LUA_BASE64_END" >> "$OUTPUT"

# Convert to Windows CRLF line endings
unix2dos -q "$OUTPUT"

echo "Built installer: $OUTPUT"
