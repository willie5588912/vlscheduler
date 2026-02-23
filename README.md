VLScheduler
===========

A VLC extension that schedules automatic playlist playback on specific weekdays and times.

Set up weekly schedules (e.g., play a playlist every Monday at 22:30) through a simple GUI inside VLC. No command-line flags needed — just configure and go.

Currently **Windows only**.

## Quick Start

1. Download `vlscheduler-<version>-install.cmd` from the [Releases](https://github.com/willie5588912/vlscheduler/releases) page
2. Double-click the `.cmd` file — it will request admin permission, then show a setup window
3. Click **Install**
4. Open VLC, go to **View > VLScheduler > Schedule Setup**
5. Set the playback time, check the weekdays you want, browse for media files, and click **Save**
6. VLC will automatically play the scheduled playlists at the configured times

To uninstall, run the same `.cmd` file and click **Uninstall**.

## Tested Environment

- Windows 10 (build 19045)
- VLC 3.0.23 (32-bit)
- MSYS2 / MinGW for building

## Building from Source

### Prerequisites

- [MSYS2](https://www.msys2.org/) with MinGW toolchain:
  ```bash
  pacman -S mingw-w64-i686-gcc make
  ```
- [VLC 3.x](https://www.videolan.org/vlc/) installed in Program Files
- VLC 3.x headers in `vlc3/include/` (included in repo)

### Build

```bash
make windows        # compile libscheduler_plugin.dll
make install        # copy DLL + Lua extension to VLC directories
make installer      # generate self-contained .cmd installer
```

## Components

| Component | File | Purpose |
|-----------|------|---------|
| Lua extension | `vlscheduler.lua` | GUI for configuring schedules |
| C plugin | `libscheduler_plugin.dll` | Engine that triggers playback at scheduled times |
| Installer builder | `build_installer.sh` | Generates a single `.cmd` installer with embedded binaries |

## License

[GPL v2+](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
