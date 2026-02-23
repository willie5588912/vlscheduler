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
local OS = nil
local dlg = nil
local days = {}          -- [1..7], each: {enabled, hour, minute, info}
local selected_files = {} -- [1..7], each: table of absolute file paths
local status_label = nil
local file_list = nil

-- "Same time" widgets
local same_time_cb = nil
local same_hour = nil
local same_minute = nil

-- Windows folder browser state
local browse_mode = false
local browse_day = nil
local current_path = ""
local browser_entries = {}  -- {name, is_dir, full_path} indexed by list id
local path_input = nil      -- text input showing current path
local btn_up = nil
local btn_open = nil
local btn_use = nil

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
        capabilities = {"menu"}
    }
end

function activate()
    OS = detect_os()
    dbg("activate() OS=" .. tostring(OS))
    for i = 1, 7 do
        selected_files[i] = {}
    end
    create_dialog()
    click_load()
    dbg("activate() done")
end

function deactivate()
    if dlg then
        dlg:hide()
    end
end

function close()
    vlc.deactivate()
end

function menu()
    return {"Schedule Setup"}
end

function trigger_menu(id)
    if id == 1 then
        create_dialog()
        click_load()
    end
end

---------------------------------------------------------------------------
-- Platform detection
---------------------------------------------------------------------------
function detect_os()
    -- Use VLC's native platform flag when available
    if vlc.win then
        return "windows"
    end
    -- Fallback: probe via config dir path
    local dir = vlc.config.userdatadir() or ""
    if string.find(dir, "/Library/") or string.find(dir, "org%.videolan%.vlc") then
        return "macos"
    end
    return "linux"
end

---------------------------------------------------------------------------
-- Debug logging (writes + flushes to file immediately)
---------------------------------------------------------------------------
local DEBUG_LOG = "C:\\Users\\admin\\vlscheduler-debug.log"

function dbg(msg)
    local f = vlc.io.open(DEBUG_LOG, "a")
    if f then
        f:write(os.date("%H:%M:%S") .. " " .. msg .. "\n")
        f:close()
    end
end

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

---------------------------------------------------------------------------
-- Windows folder browser
---------------------------------------------------------------------------
function is_directory(path)
    local ok, entries = pcall(vlc.net.opendir, path)
    return ok and entries ~= nil
end

function get_parent_path(path)
    -- Remove trailing separator
    path = string.gsub(path, "[/\\]+$", "")
    local parent = string.match(path, "^(.*)[/\\]")
    if not parent or parent == "" then
        -- We're at a drive root like C:
        return nil
    end
    -- If parent is just "C:", add backslash
    if string.match(parent, "^%a:$") then
        return parent .. "\\"
    end
    return parent
end

function refresh_browser(path)
    current_path = path
    browser_entries = {}
    file_list:clear()

    if path_input then
        path_input:set_text(path)
    end

    local ok, entries = pcall(vlc.net.opendir, path)
    if not ok or not entries then
        status_label:set_text("Cannot read: " .. path)
        dlg:update()
        return
    end

    table.sort(entries, function(a, b)
        return string.lower(a) < string.lower(b)
    end)

    local id = 1
    local sep = (OS == "windows") and "\\" or "/"
    -- Ensure path ends with separator
    if string.sub(path, -1) ~= sep and string.sub(path, -1) ~= "/" then
        path = path .. sep
    end

    -- Add directories first, then media files
    local dirs = {}
    local media = {}
    for _, name in ipairs(entries) do
        if name ~= "." and name ~= ".." then
            local full = path .. name
            if is_directory(full) then
                table.insert(dirs, {name = name, full_path = full})
            elseif is_media_file(name) then
                table.insert(media, {name = name, full_path = full})
            end
        end
    end

    for _, d in ipairs(dirs) do
        file_list:add_value("[DIR]  " .. d.name, id)
        browser_entries[id] = {name = d.name, is_dir = true, full_path = d.full_path}
        id = id + 1
    end
    for _, m in ipairs(media) do
        file_list:add_value("       " .. m.name, id)
        browser_entries[id] = {name = m.name, is_dir = false, full_path = m.full_path}
        id = id + 1
    end

    local media_count = #media
    status_label:set_text("Browsing for " .. DAY_NAMES[browse_day]
        .. " | " .. #dirs .. " folder(s), " .. media_count .. " media file(s)")
    dlg:update()
end

function enter_browse_mode(day_index)
    browse_mode = true
    browse_day = day_index
    local start_path = "C:\\"
    if OS ~= "windows" then
        start_path = "/"
    end
    refresh_browser(start_path)
end

function exit_browse_mode()
    browse_mode = false
    browse_day = nil
    browser_entries = {}
    file_list:clear()
    if path_input then
        path_input:set_text("")
    end
    status_label:set_text("Ready.")
    dlg:update()
end

function click_browser_open()
    if not browse_mode then return end
    local sel = file_list:get_value()
    if not sel or not browser_entries[sel] then
        status_label:set_text("Select a [DIR] folder from the list, then click Open.")
        dlg:update()
        return
    end
    local entry = browser_entries[sel]
    if entry.is_dir then
        refresh_browser(entry.full_path)
    else
        status_label:set_text("'" .. entry.name .. "' is a file, not a folder. Select a [DIR] entry.")
        dlg:update()
    end
end

function click_browser_up()
    if not browse_mode then return end
    local parent = get_parent_path(current_path)
    if parent then
        refresh_browser(parent)
    else
        status_label:set_text("Already at root.")
        dlg:update()
    end
end

function click_browser_go()
    if not browse_mode then return end
    local path = path_input:get_text()
    if path and path ~= "" then
        refresh_browser(path)
    end
end

function click_use_files()
    if not browse_mode or not browse_day then return end
    -- Collect all media files in current directory
    local files = {}
    for _, entry in pairs(browser_entries) do
        if not entry.is_dir then
            table.insert(files, entry.full_path)
        end
    end
    table.sort(files)

    if #files > 0 then
        selected_files[browse_day] = files
        days[browse_day].info:set_text(#files .. " file(s)")
        status_label:set_text(DAY_NAMES[browse_day] .. ": Selected "
            .. #files .. " media file(s) from " .. current_path)
    else
        status_label:set_text("No media files in " .. current_path)
    end

    exit_browse_mode()

    -- Show the selected files in the list
    if #files > 0 then
        file_list:clear()
        for idx, filepath in ipairs(files) do
            file_list:add_value(basename(filepath), idx)
        end
    end
    dlg:update()
end

---------------------------------------------------------------------------
-- browse_files: entry point for all platforms
---------------------------------------------------------------------------
function browse_files(day_index)
    dbg("browse_files() day=" .. tostring(day_index) .. " OS=" .. tostring(OS))
    sync_if_same_time()

    if OS == "windows" then
        dbg("browse_files() windows file picker")
        -- Write selected files to a temp file in UTF-8, then read it
        local tmp = os.tmpname()
        local cmd = 'powershell -NoProfile -WindowStyle Hidden -Command "'
            .. "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8;"
            .. "Add-Type -AssemblyName System.Windows.Forms;"
            .. "$f = New-Object System.Windows.Forms.OpenFileDialog;"
            .. "$f.Multiselect = $true;"
            .. "$f.Filter = 'Media files|*.mp4;*.mkv;*.avi;*.mov;*.m4v;*.ts;"
            .. "*.flv;*.wmv;*.mpg;*.mpeg;*.mp3;*.flac;*.wav;*.aiff;*.m4a;*.ogg';"
            .. "$f.Title = 'Select media files for " .. DAY_NAMES[day_index] .. "';"
            .. "if ($f.ShowDialog() -eq 'OK') {"
            .. " $f.FileNames | Out-File -Encoding utf8 -FilePath '"
            .. string.gsub(tmp, "/", "\\") .. "'"
            .. "}"
            .. '"'
        os.execute(cmd)
        dbg("browse_files() command finished, reading temp file: " .. tmp)

        local f = vlc.io.open(tmp, "r")
        if not f then
            dbg("browse_files() no temp file (user cancelled?)")
            os.remove(tmp)
            return
        end

        local files = {}
        while true do
            local line = f:read("*l")
            if not line then break end
            line = string.match(line, "^%s*(.-)%s*$")
            -- Skip BOM if present
            if string.byte(line, 1) == 239 and string.byte(line, 2) == 187
               and string.byte(line, 3) == 191 then
                line = string.sub(line, 4)
                line = string.match(line, "^%s*(.-)%s*$")
            end
            if line ~= "" then
                table.insert(files, line)
            end
        end
        f:close()
        os.remove(tmp)
        dbg("browse_files() parsed " .. #files .. " files")

        if #files > 0 then
            selected_files[day_index] = files
            days[day_index].info:set_text(#files .. " file(s)")
            file_list:clear()
            for idx, filepath in ipairs(files) do
                file_list:add_value(basename(filepath), idx)
            end
            status_label:set_text(DAY_NAMES[day_index] .. ": Selected " .. #files .. " file(s)")
        end
        dlg:update()
        dbg("browse_files() done")
        return
    end

    local cmd
    if OS == "macos" then
        cmd = browse_files_macos(day_index)
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
        local ok, err = pcall(browse_files, day_index)
        if not ok then
            status_label:set_text("Error: " .. tostring(err))
            dlg:update()
        end
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

    -- Row 11: Browser navigation bar (Windows only)
    if OS == "windows" then
        path_input = dlg:add_text_input("C:\\", 1, 11, 3, 1)
        dlg:add_button("Go", click_browser_go, 4, 11, 1, 1)
        btn_up = dlg:add_button("Up", click_browser_up, 5, 11, 1, 1)
        btn_open = dlg:add_button("Open", click_browser_open, 6, 11, 1, 1)
    end

    -- Row 12: File list
    local list_row = (OS == "windows") and 12 or 11
    file_list = dlg:add_list(1, list_row, 6, 1)

    -- Row 13: Status + action buttons
    local status_row = list_row + 1
    if OS == "windows" then
        status_label = dlg:add_label("Click Browse to select files.", 1, status_row, 2, 1)
        btn_use = dlg:add_button("Use Files", click_use_files, 3, status_row, 1, 1)
        dlg:add_button("Cancel", click_cancel, 5, status_row, 1, 1)
        dlg:add_button("Save", click_save, 6, status_row, 1, 1)
    else
        status_label = dlg:add_label(
            "Ready. Browse to select files, then Save.",
            1, status_row, 4, 1)
        dlg:add_button("Cancel", click_cancel, 5, status_row, 1, 1)
        dlg:add_button("Save", click_save, 6, status_row, 1, 1)
    end

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
    -- 1. Set in-memory config so VLC persists it to vlcrc on clean exit
    pcall(function()
        local current = vlc.config.get("extraintf") or ""
        if not string.find(current, "scheduler") then
            local sep = (OS == "windows") and ";" or ":"
            if current == "" then
                vlc.config.set("extraintf", "scheduler")
            else
                vlc.config.set("extraintf", current .. sep .. "scheduler")
            end
        end
    end)

    pcall(function()
        vlc.config.set("scheduler-config", conf_path)
    end)

    -- 2. Also directly patch vlcrc file as backup (in case VLC doesn't
    --    exit cleanly, the in-memory config never gets written)
    pcall(function()
        local vlcrc_path = vlc.config.userdatadir() .. "/vlcrc"
        local f = vlc.io.open(vlcrc_path, "r")
        if not f then return end

        local lines = {}
        local found_extraintf = false
        local already_set = false
        while true do
            local line = f:read("*l")
            if not line then break end
            -- Check if this is the extraintf line
            if string.match(line, "^#?extraintf=") then
                found_extraintf = true
                local value = string.match(line, "^#?extraintf=(.*)$") or ""
                if string.find(value, "scheduler") then
                    already_set = true
                    table.insert(lines, "extraintf=" .. value)
                elseif value == "" then
                    table.insert(lines, "extraintf=scheduler")
                else
                    local sep = (OS == "windows") and ";" or ":"
                    table.insert(lines, "extraintf=" .. value .. sep .. "scheduler")
                end
            else
                table.insert(lines, line)
            end
        end
        f:close()

        if already_set then return end

        local fw = vlc.io.open(vlcrc_path, "w")
        if not fw then return end
        for _, l in ipairs(lines) do
            fw:write(l .. "\n")
        end
        fw:close()
        dbg("ensure_scheduler_autostart() patched vlcrc")
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
