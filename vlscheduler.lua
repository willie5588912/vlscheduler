--[[
  VLScheduler - Scheduled Playlist Playback for VLC
  Copyright (C) 2026 Wei Shih

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.

  Install: copy vlscheduler.lua to VLC's lua/extensions/ directory.
  Access via View > VLScheduler (or VLC > Extensions > VLScheduler on macOS).
  Homepage: https://github.com/user/vlscheduler
]]--

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local MEDIA_EXTENSIONS = {
    mp4=true, mkv=true, avi=true, mov=true, m4v=true, ts=true,
    flv=true, wmv=true, mpg=true, mpeg=true,
    mp3=true, flac=true, wav=true, aiff=true, m4a=true, ogg=true
}

local DAY_NAMES    = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
local DAY_ABBREVS  = {"SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"}
local DAY_FILENAMES = {
    "sunday", "monday", "tuesday", "wednesday",
    "thursday", "friday", "saturday"
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local dlg = nil
local days = {}          -- [1..7], each: {enabled, hour, minute, info}
local selected_files = {} -- [1..7], each: table of absolute file paths
local status_label = nil
local file_list = nil

-- "Same time" widgets
local same_time_cb = nil
local same_hour = nil
local same_minute = nil

---------------------------------------------------------------------------
-- Extension lifecycle
---------------------------------------------------------------------------
function descriptor()
    return {
        title = "VLScheduler",
        version = "0.0.1",
        author = "Wei Shih",
        url = "https://github.com/user/vlscheduler",
        shortdesc = "VLScheduler",
        description = "Schedule automatic playlist playback on specific "
                   .. "weekdays and times. Select days, set times, choose "
                   .. "media files, and VLC will play them on schedule.",
        capabilities = {}
    }
end

function activate()
    for i = 1, 7 do
        selected_files[i] = {}
    end
    create_dialog()
    click_load()
end

function deactivate()
    if dlg then
        dlg:hide()
    end
end

function close()
    vlc.deactivate()
end

---------------------------------------------------------------------------
-- Platform detection
---------------------------------------------------------------------------
function detect_os()
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
        return "windows"
    end
    -- Distinguish macOS from Linux
    local ok, handle = pcall(io.popen, "uname -s 2>/dev/null")
    if ok and handle then
        local result = handle:read("*l")
        handle:close()
        if result and result:find("Darwin") then
            return "macos"
        end
    end
    return "linux"
end

local OS = detect_os()

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function get_config_dir()
    local base = vlc.config.userdatadir()
    local dir = base .. "/scheduler"
    vlc.io.mkdir(dir, "0755")
    return dir
end

function is_media_file(filename)
    local ext = string.match(filename, "%.([^%.]+)$")
    if ext and MEDIA_EXTENSIONS[string.lower(ext)] then
        return true
    end
    return false
end

function parse_time(hour_widget, minute_widget)
    local h = tonumber(hour_widget:get_text()) or 0
    local m = tonumber(minute_widget:get_text()) or 0
    if h < 0 then h = 0 end
    if h > 23 then h = 23 end
    if m < 0 then m = 0 end
    if m > 59 then m = 59 end
    return h, m
end

function sync_if_same_time()
    if same_time_cb and same_time_cb:get_checked() then
        local ht = same_hour:get_text()
        local mt = same_minute:get_text()
        for i = 1, 7 do
            if days[i] and days[i].hour then
                days[i].hour:set_text(ht)
                days[i].minute:set_text(mt)
            end
        end
    end
end

function basename(filepath)
    return string.match(filepath, "([^/\\]+)$") or filepath
end

function extract_files_from_m3u(m3u_path)
    local f = vlc.io.open(m3u_path, "r")
    if not f then return nil end

    local files = {}
    while true do
        local line = f:read("*l")
        if not line then break end
        line = string.match(line, "^%s*(.-)%s*$")
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            table.insert(files, line)
        end
    end
    f:close()
    return files
end

---------------------------------------------------------------------------
-- File picker (cross-platform)
---------------------------------------------------------------------------
function browse_files_macos(day_index)
    local cmd = 'osascript -e \'set theFiles to choose file '
             .. 'of type {"public.movie","public.audio","public.mpeg-4",'
             .. '"com.apple.m4v-video","public.avi","com.microsoft.windows-media-wmv"} '
             .. 'with multiple selections allowed '
             .. 'with prompt "Select media files for '
             .. DAY_NAMES[day_index] .. '"\' '
             .. '-e \'set output to ""\' '
             .. '-e \'repeat with f in theFiles\' '
             .. '-e \'set output to output & POSIX path of f & linefeed\' '
             .. '-e \'end repeat\' '
             .. '-e \'return output\' 2>/dev/null'
    return cmd
end

function browse_files_linux(day_index)
    -- Try zenity first (GNOME), then kdialog (KDE)
    return 'zenity --file-selection --multiple --separator=$\'\\n\' '
        .. '--file-filter="Media files|*.mp4 *.mkv *.avi *.mov *.m4v '
        .. '*.ts *.flv *.wmv *.mpg *.mpeg *.mp3 *.flac *.wav *.aiff '
        .. '*.m4a *.ogg" '
        .. '--title="Select media files for ' .. DAY_NAMES[day_index] .. '" '
        .. '2>/dev/null || '
        .. 'kdialog --getopenfilename "$HOME" '
        .. '"*.mp4 *.mkv *.avi *.mov *.m4v *.ts *.flv *.wmv *.mpg '
        .. '*.mpeg *.mp3 *.flac *.wav *.aiff *.m4a *.ogg|Media files" '
        .. '--multiple --separate-output '
        .. '--title "Select media files for ' .. DAY_NAMES[day_index] .. '" '
        .. '2>/dev/null'
end

function browse_files_windows(day_index)
    -- PowerShell file dialog
    return 'powershell -NoProfile -Command "'
        .. '[System.Reflection.Assembly]::LoadWithPartialName(\\"System.Windows.Forms\\") | Out-Null; '
        .. '$d = New-Object System.Windows.Forms.OpenFileDialog; '
        .. '$d.Title = \\"Select media files for ' .. DAY_NAMES[day_index] .. '\\"; '
        .. '$d.Filter = \\"Media files|*.mp4;*.mkv;*.avi;*.mov;*.m4v;*.ts;*.flv;*.wmv;*.mpg;*.mpeg;*.mp3;*.flac;*.wav;*.aiff;*.m4a;*.ogg\\"; '
        .. '$d.Multiselect = $true; '
        .. 'if ($d.ShowDialog() -eq \\"OK\\") { $d.FileNames -join [char]10 }'
        .. '"'
end

function browse_files(day_index)
    sync_if_same_time()

    local cmd
    if OS == "macos" then
        cmd = browse_files_macos(day_index)
    elseif OS == "windows" then
        cmd = browse_files_windows(day_index)
    else
        cmd = browse_files_linux(day_index)
    end

    local handle = io.popen(cmd)
    if not handle then
        status_label:set_text("Error: Could not open file picker")
        dlg:update()
        return
    end

    local result = handle:read("*a")
    handle:close()

    if not result or result == "" then
        return
    end

    local files = {}
    for path in string.gmatch(result, "[^\n\r]+") do
        path = string.match(path, "^%s*(.-)%s*$")
        if path ~= "" then
            table.insert(files, path)
        end
    end

    if #files > 0 then
        selected_files[day_index] = files
        days[day_index].info:set_text(#files .. " file(s)")

        file_list:clear()
        for idx, filepath in ipairs(files) do
            file_list:add_value(basename(filepath), idx)
        end

        status_label:set_text(DAY_NAMES[day_index] .. ": Selected "
                              .. #files .. " file(s)")
    end

    dlg:update()
end

---------------------------------------------------------------------------
-- Dialog construction
---------------------------------------------------------------------------
function make_show_callback(day_index)
    return function()
        show_files(day_index)
    end
end

function make_browse_callback(day_index)
    return function()
        browse_files(day_index)
    end
end

function create_dialog()
    dlg = vlc.dialog("VLScheduler")

    -- Row 1: Header
    dlg:add_label("<h3>VLScheduler</h3>", 1, 1, 6, 1)

    -- Row 2: Same time option
    same_time_cb = dlg:add_check_box("Same time for all", false, 1, 2, 2, 1)
    same_hour = dlg:add_text_input("00", 3, 2, 1, 1)
    dlg:add_label(":", 4, 2, 1, 1)
    same_minute = dlg:add_text_input("00", 5, 2, 1, 1)

    -- Row 3: Column headers
    dlg:add_label("<b>Day</b>", 1, 3, 1, 1)
    dlg:add_label("<b>Hour</b>", 2, 3, 1, 1)
    dlg:add_label("", 3, 3, 1, 1)
    dlg:add_label("<b>Min</b>", 4, 3, 1, 1)
    dlg:add_label("<b>Files</b>", 5, 3, 1, 1)
    dlg:add_label("", 6, 3, 1, 1)

    -- Rows 4-10: One per weekday
    for i = 1, 7 do
        local row = i + 3
        days[i] = {}

        days[i].enabled = dlg:add_check_box(DAY_NAMES[i], false, 1, row, 1, 1)
        days[i].hour = dlg:add_text_input("00", 2, row, 1, 1)
        dlg:add_label(":", 3, row, 1, 1)
        days[i].minute = dlg:add_text_input("00", 4, row, 1, 1)
        days[i].info = dlg:add_button("No files", make_show_callback(i), 5, row, 1, 1)
        dlg:add_button("Browse", make_browse_callback(i), 6, row, 1, 1)
    end

    -- Row 11: File list
    file_list = dlg:add_list(1, 11, 6, 1)

    -- Row 12: Status + action buttons
    status_label = dlg:add_label(
        "Ready. Browse to select files, then Save.",
        1, 12, 4, 1)
    dlg:add_button("Cancel", click_cancel, 5, 12, 1, 1)
    dlg:add_button("Save", click_save, 6, 12, 1, 1)

    dlg:show()
end

---------------------------------------------------------------------------
-- Core operations
---------------------------------------------------------------------------
function show_files(day_index)
    sync_if_same_time()
    local files = selected_files[day_index]
    file_list:clear()

    if not files or #files == 0 then
        status_label:set_text(DAY_NAMES[day_index] .. ": No files selected")
    else
        for idx, filepath in ipairs(files) do
            file_list:add_value(basename(filepath), idx)
        end
        status_label:set_text(DAY_NAMES[day_index] .. ": " .. #files .. " file(s)")
    end

    dlg:update()
end

function write_m3u(files, output_path)
    if #files == 0 then
        return false, "No files to write"
    end

    local f = vlc.io.open(output_path, "w")
    if not f then
        return false, "Cannot write to " .. output_path
    end

    f:write("#EXTM3U\n")
    for _, filepath in ipairs(files) do
        f:write("#EXTINF:-1," .. basename(filepath) .. "\n")
        f:write(filepath .. "\n")
    end
    f:close()

    return true, nil
end

function ensure_scheduler_autostart(conf_path)
    -- Set in-memory config so VLC persists it to vlcrc on exit.
    -- This is the reliable approach: VLC overwrites vlcrc on exit
    -- from memory, so direct file edits get lost.
    pcall(function()
        local current = vlc.config.get("extraintf") or ""
        if not string.find(current, "scheduler") then
            -- VLC uses ":" as separator on Unix, ";" on Windows
            local sep = (OS == "windows") and ";" or ":"
            if current == "" then
                vlc.config.set("extraintf", "scheduler")
            else
                vlc.config.set("extraintf", current .. sep .. "scheduler")
            end
        end
    end)

    -- Also set scheduler-config (only works if C plugin is loaded)
    pcall(function()
        vlc.config.set("scheduler-config", conf_path)
    end)
end

function click_cancel()
    vlc.deactivate()
end

function click_save()
    sync_if_same_time()
    local config_dir = get_config_dir()
    local conf_lines = {}
    local errors = {}
    local count = 0

    local use_same_time = same_time_cb:get_checked()
    local shared_h, shared_m = parse_time(same_hour, same_minute)

    for i = 1, 7 do
        if days[i].enabled:get_checked() then
            local hour_id, min_id
            if use_same_time then
                hour_id = shared_h
                min_id = shared_m
            else
                hour_id, min_id = parse_time(days[i].hour, days[i].minute)
            end

            if #selected_files[i] == 0 then
                table.insert(errors, DAY_NAMES[i] .. ": no files selected")
            else
                local m3u_path = config_dir .. "/" .. DAY_FILENAMES[i] .. ".m3u"
                local ok, err = write_m3u(selected_files[i], m3u_path)

                if ok then
                    local line = string.format("%s  %02d:%02d  %s",
                        DAY_ABBREVS[i], hour_id, min_id, m3u_path)
                    table.insert(conf_lines, line)
                    count = count + 1
                else
                    table.insert(errors, DAY_NAMES[i] .. ": " .. (err or "unknown error"))
                end
            end
        end
    end

    if count > 0 then
        local conf_path = config_dir .. "/schedule.conf"
        local f = vlc.io.open(conf_path, "w")
        if f then
            f:write("# VLScheduler Configuration\n")
            f:write("# Generated by VLScheduler extension\n")
            f:write("#\n")
            for _, line in ipairs(conf_lines) do
                f:write(line .. "\n")
            end
            f:close()

            -- Ensure scheduler plugin auto-loads on VLC startup
            ensure_scheduler_autostart(conf_path)

            local msg = "Saved " .. count .. " schedule(s)."
            if #errors > 0 then
                msg = msg .. " (" .. #errors .. " error(s))"
            end
            status_label:set_text(msg)
            dlg:update()
            vlc.deactivate()
            return
        else
            status_label:set_text("Error: Could not write config file")
        end
    elseif #errors > 0 then
        status_label:set_text("Errors: " .. table.concat(errors, "; "))
    else
        status_label:set_text("Nothing to save -- no days are enabled.")
    end

    dlg:update()
end

function click_load()
    local config_dir = get_config_dir()
    local conf_path = config_dir .. "/schedule.conf"

    local f = vlc.io.open(conf_path, "r")
    if not f then
        local alt_path = nil
        pcall(function() alt_path = vlc.config.get("scheduler-config") end)
        if alt_path and alt_path ~= "" then
            f = vlc.io.open(alt_path, "r")
            conf_path = alt_path
        end
        if not f then
            return
        end
    end

    -- Reset all days
    for i = 1, 7 do
        days[i].enabled:set_checked(false)
        days[i].hour:set_text("00")
        days[i].minute:set_text("00")
        days[i].info:set_text("No files")
        selected_files[i] = {}
    end

    local day_map = {
        SUN = 1, MON = 2, TUE = 3, WED = 4,
        THU = 5, FRI = 6, SAT = 7
    }

    local all_hours = {}
    local all_mins = {}
    local entries = {}

    while true do
        local line = f:read("*l")
        if not line then break end

        line = string.match(line, "^%s*(.-)%s*$")
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            local day_str, hour, minute, path =
                string.match(line, "^(%a+)%s+(%d+):(%d+)%s+(.+)$")
            if day_str and hour and minute and path then
                table.insert(entries, {
                    day = string.upper(day_str),
                    hour = tonumber(hour),
                    minute = tonumber(minute),
                    path = path
                })
                table.insert(all_hours, tonumber(hour))
                table.insert(all_mins, tonumber(minute))
            end
        end
    end
    f:close()

    -- Detect if all entries use the same time
    local all_same = #entries > 1
    for i = 2, #all_hours do
        if all_hours[i] ~= all_hours[1] or all_mins[i] ~= all_mins[1] then
            all_same = false
            break
        end
    end
    if all_same and #entries > 0 then
        same_time_cb:set_checked(true)
        same_hour:set_text(string.format("%02d", all_hours[1]))
        same_minute:set_text(string.format("%02d", all_mins[1]))
    else
        same_time_cb:set_checked(false)
    end

    -- Apply entries
    local count = 0
    for _, entry in ipairs(entries) do
        local idx = day_map[entry.day]
        if idx then
            days[idx].enabled:set_checked(true)
            days[idx].hour:set_text(string.format("%02d", entry.hour))
            days[idx].minute:set_text(string.format("%02d", entry.minute))

            local files = extract_files_from_m3u(entry.path)
            if files and #files > 0 then
                selected_files[idx] = files
                days[idx].info:set_text(#files .. " file(s)")
            else
                days[idx].info:set_text(entry.path)
            end
            count = count + 1
        end
    end

    file_list:clear()
    if count > 0 then
        status_label:set_text("Loaded " .. count .. " schedule(s).")
    end
    dlg:update()
end
