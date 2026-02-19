VLScheduler
===========

VLC extension to schedule automatic playlist playback on specific weekdays and times.

Set up weekly schedules (e.g., play a playlist every Monday at 22:30) through a simple GUI inside VLC. No command-line flags needed — just configure and go.

Author: Wei Shih
Homepage: https://github.com/user/vlscheduler
License: [GPL v2+](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

## Features

- Per-weekday scheduling with individual times
- "Same time for all" option for uniform schedules
- Native file picker to select media files (macOS, Linux, Windows)
- Auto-generates M3U playlists and schedule config
- Hot-reload: config changes take effect within 30 seconds, no VLC restart needed
- Auto-starts on VLC launch after first save

## Components

VLScheduler has two parts:

| Component | File | Purpose |
|-----------|------|---------|
| Lua extension | `vlscheduler.lua` | GUI for configuring schedules |
| C plugin | `libscheduler_plugin.*` | Engine that triggers playback at scheduled times |

Both must be installed for full functionality.

## Installation

### Lua Extension (vlscheduler.lua)

Copy `vlscheduler.lua` to VLC's Lua extensions directory:

- **macOS (all users):** `/Applications/VLC.app/Contents/MacOS/share/lua/extensions/`
- **macOS (current user):** `~/Library/Application Support/org.videolan.vlc/lua/extensions/`
- **Linux (all users):** `/usr/lib/vlc/lua/extensions/`
- **Linux (current user):** `~/.local/share/vlc/lua/extensions/`
- **Windows (all users):** `%ProgramFiles%\VideoLAN\VLC\lua\extensions\`
- **Windows (current user):** `%APPDATA%\vlc\lua\extensions\`

### C Plugin (scheduler engine)

#### Using prebuilt binaries

Copy the appropriate binary to VLC's plugin directory:

- **macOS:** `/Applications/VLC.app/Contents/MacOS/plugins/`
- **Linux:** `/usr/lib/vlc/plugins/misc/` or `~/.local/share/vlc/plugins/`
- **Windows:** `%ProgramFiles%\VideoLAN\VLC\plugins\misc\`

#### Building from source

Requires VLC 3.x development headers.

```bash
git clone https://github.com/user/vlscheduler.git
cd vlscheduler
make
make install
```

The Makefile auto-detects your platform and builds the correct library format (`.dylib` / `.so` / `.dll`).

## Usage

1. Open VLC
2. Go to **View > VLScheduler** (or **VLC > Extensions > VLScheduler** on macOS)
3. Check the weekdays you want to schedule
4. Set the time (hour and minute) for each day
5. Click **Browse** to select media files for each day
6. Click **Save**
7. Quit and reopen VLC once (to activate the scheduler engine)

From then on, VLC will automatically play the scheduled playlists at the configured times. Config changes are hot-reloaded — no restart needed after the initial setup.

### "Same time for all" option

Check the "Same time for all" checkbox and set a shared time. All enabled weekdays will use this time when you save.

## Configuration Files

VLScheduler stores its configuration in VLC's user data directory:

| Platform | Path |
|----------|------|
| macOS | `~/Library/Application Support/org.videolan.vlc/scheduler/` |
| Linux | `~/.local/share/vlc/scheduler/` |
| Windows | `%APPDATA%\vlc\scheduler\` |

Contents:
- `schedule.conf` — schedule rules (read by the C plugin)
- `{weekday}.m3u` — auto-generated playlists for each enabled day

### Config format

The `schedule.conf` file uses a simple text format:

```
MON  22:30  /path/to/monday.m3u
WED  22:30  /path/to/wednesday.m3u
FRI  19:00  /path/to/friday.m3u
```

Each line: `DAY  HH:MM  /path/to/playlist.m3u`

## Compatibility

- **VLC 3.x** (tested with VLC 3.0.x)
- **macOS:** Full support including native file picker
- **Linux:** File picker via zenity (GNOME) or kdialog (KDE)
- **Windows:** File picker via PowerShell dialog

## Changelog

### 0.0.1 (2026-02-20)
- Initial release
- Per-weekday scheduling with GUI configuration
- Cross-platform file picker (macOS, Linux, Windows)
- Config hot-reload without VLC restart
- Auto-start scheduler on VLC launch
