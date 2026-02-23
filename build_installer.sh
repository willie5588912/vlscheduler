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

# --- Write the batch launcher ---
cat > "$OUTPUT" << 'BATCH_HEADER'
@echo off
:: VLScheduler Installer - Self-contained installer with GUI
:: This file embeds the plugin DLL and Lua extension as base64.

:: Request admin elevation if not already elevated
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b 0
)

:: Extract the embedded PowerShell script to a temp file and run it
set "PS_TMP=%TEMP%\vlscheduler_setup.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$c = [IO.File]::ReadAllText('%~f0', [Text.Encoding]::ASCII);" ^
  "$m = [regex]::Match($c, '::PS_SCRIPT_START\r?\n([\s\S]*?)::PS_SCRIPT_END');" ^
  "if (-not $m.Success) { Write-Error 'Script not found'; exit 1 };" ^
  "[IO.File]::WriteAllText('%PS_TMP%', $m.Groups[1].Value, [Text.Encoding]::UTF8)"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_TMP%" "%~f0"
del "%PS_TMP%" 2>nul
exit /b 0

::PS_SCRIPT_START
param([string]$ScriptPath)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'

# ---- Detect VLC ----
$vlcDir = $null
foreach ($d in @("$env:ProgramFiles\VideoLAN\VLC", "${env:ProgramFiles(x86)}\VideoLAN\VLC")) {
    if (Test-Path "$d\vlc.exe") { $vlcDir = $d; break }
}

$pluginDir = if ($vlcDir) { "$vlcDir\plugins\misc" } else { $null }
$extDir = "$env:APPDATA\vlc\lua\extensions"

$dllName = 'libscheduler_plugin.dll'
$luaName = 'vlscheduler.lua'

# ---- Check installed status ----
function Get-InstalledStatus {
    $dllOk = $pluginDir -and (Test-Path "$pluginDir\$dllName")
    $luaOk = Test-Path "$extDir\$luaName"
    return ($dllOk -and $luaOk)
}

# ---- Extract embedded base64 data ----
function Extract-Files {
    param($tmpDir)
    $raw = [IO.File]::ReadAllText($ScriptPath, [Text.Encoding]::ASCII)
    $dllMatch = [regex]::Match($raw, '::DLL_BASE64_START\r?\n([\s\S]*?)::DLL_BASE64_END')
    $luaMatch = [regex]::Match($raw, '::LUA_BASE64_START\r?\n([\s\S]*?)::LUA_BASE64_END')
    if (-not $dllMatch.Success -or -not $luaMatch.Success) {
        throw 'Failed to extract embedded data'
    }
    $dllB64 = $dllMatch.Groups[1].Value -replace '\s',''
    $luaB64 = $luaMatch.Groups[1].Value -replace '\s',''
    [IO.File]::WriteAllBytes("$tmpDir\$dllName", [Convert]::FromBase64String($dllB64))
    $luaBytes = [Convert]::FromBase64String($luaB64)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText("$tmpDir\$luaName", $utf8.GetString($luaBytes), $utf8)
}

# ---- Check if VLC is running ----
function Test-VlcRunning {
    return [bool](Get-Process vlc -ErrorAction SilentlyContinue)
}

# ---- Build the form ----
$form = New-Object System.Windows.Forms.Form
$form.Text = 'VLScheduler Setup'
$form.Size = New-Object System.Drawing.Size(420, 300)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'VLScheduler Setup'
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(20, 15)
$titleLabel.AutoSize = $true
$form.Controls.Add($titleLabel)

$vlcLabel = New-Object System.Windows.Forms.Label
$vlcLabel.Location = New-Object System.Drawing.Point(20, 55)
$vlcLabel.Size = New-Object System.Drawing.Size(360, 20)
if ($vlcDir) {
    $vlcLabel.Text = "VLC found: $vlcDir"
} else {
    $vlcLabel.Text = 'VLC not found. Please install VLC first.'
    $vlcLabel.ForeColor = [System.Drawing.Color]::Red
}
$form.Controls.Add($vlcLabel)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(20, 80)
$statusLabel.Size = New-Object System.Drawing.Size(360, 20)
if (Get-InstalledStatus) {
    $statusLabel.Text = 'Status: Installed'
    $statusLabel.ForeColor = [System.Drawing.Color]::Green
} else {
    $statusLabel.Text = 'Status: Not installed'
    $statusLabel.ForeColor = [System.Drawing.Color]::Gray
}
$form.Controls.Add($statusLabel)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = 'Vertical'
$logBox.Location = New-Object System.Drawing.Point(20, 110)
$logBox.Size = New-Object System.Drawing.Size(365, 90)
$logBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($logBox)

function Log($msg) {
    $logBox.AppendText("$msg`r`n")
    $form.Refresh()
}

# ---- Install button ----
$installBtn = New-Object System.Windows.Forms.Button
$installBtn.Text = 'Install'
$installBtn.Size = New-Object System.Drawing.Size(110, 35)
$installBtn.Location = New-Object System.Drawing.Point(20, 215)
$installBtn.Enabled = [bool]$vlcDir
$installBtn.Add_Click({
    if (Test-VlcRunning) {
        Log 'Please close VLC first!'
        return
    }
    try {
        $tmp = "$env:TEMP\vlscheduler_install"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        Log 'Extracting files...'
        Extract-Files $tmp
        Log "Copying plugin to $pluginDir"
        Copy-Item "$tmp\$dllName" "$pluginDir\" -Force
        if (-not (Test-Path $extDir)) { New-Item -ItemType Directory -Path $extDir -Force | Out-Null }
        Log "Copying extension to $extDir"
        Copy-Item "$tmp\$luaName" "$extDir\" -Force
        Remove-Item "$vlcDir\plugins\plugins.dat" -ErrorAction SilentlyContinue
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Log 'Installed successfully!'
        Log 'Restart VLC, then go to View > VLScheduler.'
        $statusLabel.Text = 'Status: Installed'
        $statusLabel.ForeColor = [System.Drawing.Color]::Green
    } catch {
        Log "Error: $_"
    }
})
$form.Controls.Add($installBtn)

# ---- Uninstall button ----
$uninstallBtn = New-Object System.Windows.Forms.Button
$uninstallBtn.Text = 'Uninstall'
$uninstallBtn.Size = New-Object System.Drawing.Size(110, 35)
$uninstallBtn.Location = New-Object System.Drawing.Point(150, 215)
$uninstallBtn.Enabled = [bool]$vlcDir
$uninstallBtn.Add_Click({
    if (Test-VlcRunning) {
        Log 'Please close VLC first!'
        return
    }
    try {
        $removed = 0
        if (Test-Path "$pluginDir\$dllName") {
            Remove-Item "$pluginDir\$dllName" -Force
            Log "Removed $dllName"
            $removed++
        }
        if (Test-Path "$extDir\$luaName") {
            Remove-Item "$extDir\$luaName" -Force
            Log "Removed $luaName"
            $removed++
        }
        Remove-Item "$vlcDir\plugins\plugins.dat" -ErrorAction SilentlyContinue
        if ($removed -gt 0) {
            Log 'Uninstalled successfully!'
        } else {
            Log 'Nothing to uninstall.'
        }
        $statusLabel.Text = 'Status: Not installed'
        $statusLabel.ForeColor = [System.Drawing.Color]::Gray
    } catch {
        Log "Error: $_"
    }
})
$form.Controls.Add($uninstallBtn)

# ---- Close button ----
$closeBtn = New-Object System.Windows.Forms.Button
$closeBtn.Text = 'Close'
$closeBtn.Size = New-Object System.Drawing.Size(110, 35)
$closeBtn.Location = New-Object System.Drawing.Point(275, 215)
$closeBtn.Add_Click({ $form.Close() })
$form.Controls.Add($closeBtn)

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
::PS_SCRIPT_END
BATCH_HEADER

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
