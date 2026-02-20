# VLScheduler - Out-of-tree build for VLC 3.x
#
# Build:   make
# Install: make install      (C plugin + Lua extension)
# Package: make package      (create release ZIP)
# Clean:   make clean
#
# For Windows with MSVC, use CMakeLists.txt instead:
#   cmake -B build -DVLC_INCLUDE_DIR=path/to/vlc/sdk/include
#   cmake --build build --config Release

VERSION = 0.0.1
PLUGIN_NAME = scheduler
VLC_INCLUDE ?= ./vlc3/include

CC ?= cc

# Compiler flags
CFLAGS += -Wall -Wextra -O2 -fPIC \
          -I$(VLC_INCLUDE) \
          -D__PLUGIN__ \
          -DMODULE_STRING=\"$(PLUGIN_NAME)\" \
          -D_FILE_OFFSET_BITS=64

# Platform detection
UNAME := $(shell uname -s 2>/dev/null || echo Windows)

ifeq ($(UNAME),Darwin)
  OUTPUT = lib$(PLUGIN_NAME)_plugin.dylib
  LDFLAGS += -dynamiclib -undefined dynamic_lookup
  INSTALL_DIR ?= $(HOME)/Library/Application Support/org.videolan.vlc/plugins
  EXT_DIR ?= /Applications/VLC.app/Contents/MacOS/share/lua/extensions
  PLATFORM_TAG = macOS
else ifeq ($(UNAME),Linux)
  OUTPUT = lib$(PLUGIN_NAME)_plugin.so
  LDFLAGS += -shared
  INSTALL_DIR ?= $(HOME)/.local/share/vlc/plugins
  EXT_DIR ?= $(HOME)/.local/share/vlc/lua/extensions
  PLATFORM_TAG = Linux
else
  # Windows (MinGW / MSYS2)
  OUTPUT = $(PLUGIN_NAME)_plugin.dll
  LDFLAGS += -shared -lvlccore
  INSTALL_DIR ?= $(APPDATA)/vlc/plugins
  EXT_DIR ?= $(APPDATA)/vlc/lua/extensions
  PLATFORM_TAG = Windows
endif

.PHONY: all clean install uninstall package

all: $(OUTPUT)

$(OUTPUT): scheduler.c
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

install: $(OUTPUT)
	@mkdir -p "$(INSTALL_DIR)"
	cp $(OUTPUT) "$(INSTALL_DIR)/$(OUTPUT)"
	@mkdir -p "$(EXT_DIR)"
	cp vlscheduler.lua "$(EXT_DIR)/vlscheduler.lua"
	@echo "Installed plugin to $(INSTALL_DIR)"
	@echo "Installed extension to $(EXT_DIR)"

uninstall:
	rm -f "$(INSTALL_DIR)/$(OUTPUT)"
	rm -f "$(EXT_DIR)/vlscheduler.lua"
	@echo "Removed VLScheduler"

package: $(OUTPUT)
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
	rm -f $(OUTPUT) lib$(PLUGIN_NAME)_plugin.dylib lib$(PLUGIN_NAME)_plugin.so $(PLUGIN_NAME)_plugin.dll
	rm -f vlscheduler-*.zip
