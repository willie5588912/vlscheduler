# VLScheduler - Out-of-tree build for VLC 3.x
#
# Build:
#   make windows      (MinGW / MSYS2)
#   make linux
#   make macos
#
# Install: make install      (C plugin + Lua extension)
# Package: make package      (create release ZIP)
# Clean:   make clean

VERSION = 0.0.1
PLUGIN_NAME = scheduler
VLC_INCLUDE ?= ./vlc3/include

CC ?= gcc

# Common compiler flags
COMMON_CFLAGS = -Wall -Wextra -O2 -fPIC \
                -I$(VLC_INCLUDE) \
                -D__PLUGIN__ \
                -DMODULE_STRING=\"$(PLUGIN_NAME)\" \
                -D_FILE_OFFSET_BITS=64

# ---------------------------------------------------------------------------
# Windows (MinGW / MSYS2)
# ---------------------------------------------------------------------------
WIN_OUTPUT = $(PLUGIN_NAME)_plugin.dll
WIN_LDFLAGS = -shared -L. -lvlccore

VLC_DIR ?= $(shell \
  for d in \
    "$(PROGRAMFILES)/VideoLAN/VLC" \
    "$(ProgramFiles)/VideoLAN/VLC" \
    "/c/Program Files/VideoLAN/VLC" \
    "/c/Program Files (x86)/VideoLAN/VLC"; \
  do [ -f "$$d/libvlccore.dll" ] && echo "$$d" && break; done 2>/dev/null)

# Auto-generate import library from VLC's DLL
libvlccore.a:
ifneq ($(VLC_DIR),)
	gendef "$(VLC_DIR)/libvlccore.dll"
	dlltool -d libvlccore.def -l libvlccore.a -D libvlccore.dll
else
	@echo "ERROR: VLC not found. Set VLC_DIR=/path/to/VLC" && exit 1
endif

.PHONY: windows linux macos all clean install uninstall package

windows: export TMPDIR ?= /tmp
windows: export TMP ?= /tmp
windows: export TEMP ?= /tmp
windows: libvlccore.a
	$(CC) $(COMMON_CFLAGS) scheduler.c -o $(WIN_OUTPUT) $(WIN_LDFLAGS)
	@echo "Built $(WIN_OUTPUT)"

# ---------------------------------------------------------------------------
# Linux
# ---------------------------------------------------------------------------
LINUX_OUTPUT = lib$(PLUGIN_NAME)_plugin.so
LINUX_LDFLAGS = -shared

linux:
	$(CC) $(COMMON_CFLAGS) scheduler.c -o $(LINUX_OUTPUT) $(LINUX_LDFLAGS)
	@echo "Built $(LINUX_OUTPUT)"

# ---------------------------------------------------------------------------
# macOS
# ---------------------------------------------------------------------------
MACOS_OUTPUT = lib$(PLUGIN_NAME)_plugin.dylib
MACOS_LDFLAGS = -dynamiclib -undefined dynamic_lookup

macos:
	$(CC) $(COMMON_CFLAGS) scheduler.c -o $(MACOS_OUTPUT) $(MACOS_LDFLAGS)
	@echo "Built $(MACOS_OUTPUT)"

# ---------------------------------------------------------------------------
# Install / Uninstall / Package / Clean
# ---------------------------------------------------------------------------

# Detect which output exists for install/package targets
OUTPUT = $(wildcard $(WIN_OUTPUT) $(LINUX_OUTPUT) $(MACOS_OUTPUT))

# Platform detection: check OS variable first, then uname for MSYS2/MinGW
UNAME := $(shell uname -s 2>/dev/null)
IS_WINDOWS :=
ifeq ($(OS),Windows_NT)
  IS_WINDOWS = 1
endif
ifneq ($(filter MINGW% MSYS%,$(UNAME)),)
  IS_WINDOWS = 1
endif

ifdef IS_WINDOWS
  # Resolve APPDATA via cygpath — make may not inherit it under MSYS2/Git Bash
  WIN_APPDATA := $(shell cygpath --folder 26 2>/dev/null)
  INSTALL_DIR ?= $(VLC_DIR)/plugins/misc
  EXT_DIR ?= $(WIN_APPDATA)/vlc/lua/extensions
  PLATFORM_TAG = Windows
else
  ifeq ($(UNAME),Darwin)
    INSTALL_DIR ?= $(HOME)/Library/Application Support/org.videolan.vlc/plugins
    EXT_DIR ?= /Applications/VLC.app/Contents/MacOS/share/lua/extensions
    PLATFORM_TAG = macOS
  else
    INSTALL_DIR ?= $(HOME)/.local/share/vlc/plugins
    EXT_DIR ?= $(HOME)/.local/share/vlc/lua/extensions
    PLATFORM_TAG = Linux
  endif
endif

install:
	@if [ -z "$(OUTPUT)" ]; then echo "ERROR: No plugin built. Run make windows/linux/macos first." && exit 1; fi
	@mkdir -p "$(INSTALL_DIR)"
	cp $(OUTPUT) "$(INSTALL_DIR)/"
	@mkdir -p "$(EXT_DIR)"
	cp vlscheduler.lua "$(EXT_DIR)/vlscheduler.lua"
	@echo "Installed plugin to $(INSTALL_DIR)"
	@echo "Installed extension to $(EXT_DIR)"

uninstall:
	rm -f "$(INSTALL_DIR)/$(WIN_OUTPUT)" "$(INSTALL_DIR)/$(LINUX_OUTPUT)" "$(INSTALL_DIR)/$(MACOS_OUTPUT)"
	rm -f "$(EXT_DIR)/vlscheduler.lua"
	@echo "Removed VLScheduler"

package:
	@if [ -z "$(OUTPUT)" ]; then echo "ERROR: No plugin built. Run make windows/linux/macos first." && exit 1; fi
	@rm -rf vlscheduler-$(VERSION)
	@mkdir -p vlscheduler-$(VERSION)
	cp vlscheduler.lua vlscheduler-$(VERSION)/
	cp $(OUTPUT) vlscheduler-$(VERSION)/
	cp README.md vlscheduler-$(VERSION)/
	cp scheduler.c vlscheduler-$(VERSION)/
	cp Makefile vlscheduler-$(VERSION)/
	cp schedule.conf.example vlscheduler-$(VERSION)/
	cd vlscheduler-$(VERSION) && zip -r ../vlscheduler-$(VERSION)-$(PLATFORM_TAG).zip .
	@rm -rf vlscheduler-$(VERSION)
	@echo "Created vlscheduler-$(VERSION)-$(PLATFORM_TAG).zip"

clean:
	rm -f $(WIN_OUTPUT) $(LINUX_OUTPUT) $(MACOS_OUTPUT)
	rm -f libvlccore.a libvlccore.def
	rm -f vlscheduler-*.zip
