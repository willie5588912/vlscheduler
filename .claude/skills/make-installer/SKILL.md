---
name: make-installer
description: Build the self-contained Windows installer. Use this skill when the user says "build installer", "make installer", "create installer", or wants to generate the install .cmd file.
---

Run the installer build from the project root:

```bash
cd /c/Users/admin/vlscheduler && make installer
```

This compiles the plugin, then runs `build_installer.sh` to embed the DLL and Lua extension as base64 into a single `vlscheduler-<version>-install.cmd` file with a GUI for install/uninstall.
