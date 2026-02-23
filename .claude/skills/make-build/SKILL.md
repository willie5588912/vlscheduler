---
name: make-build
description: Build the VLC scheduler plugin binary. Use this skill when the user says "build", "make build", "compile", or wants to rebuild the DLL.
---

Run the build from the project root:

```bash
cd /c/Users/admin/vlscheduler && make windows
```

This compiles `scheduler.c` into `libscheduler_plugin.dll` using MinGW.
