# VLC Scheduler Plugin - Out-of-tree build
#
# Build:   make
# Install: make install
# Clean:   make clean

PLUGIN_NAME = scheduler
VLC_INCLUDE = ./vlc3/include

CC ?= cc

# Compiler flags
CFLAGS += -Wall -Wextra -O2 -fPIC \
          -I$(VLC_INCLUDE) \
          -D__PLUGIN__ \
          -DMODULE_STRING=\"$(PLUGIN_NAME)\" \
          -D_FILE_OFFSET_BITS=64

# Platform detection
UNAME := $(shell uname -s)

ifeq ($(UNAME),Darwin)
  OUTPUT = lib$(PLUGIN_NAME)_plugin.dylib
  LDFLAGS += -dynamiclib -undefined dynamic_lookup
  # Default install to user VLC plugins directory
  INSTALL_DIR ?= $(HOME)/Library/Application Support/org.videolan.vlc/plugins
else ifeq ($(UNAME),Linux)
  OUTPUT = lib$(PLUGIN_NAME)_plugin.so
  LDFLAGS += -shared
  INSTALL_DIR ?= $(HOME)/.local/share/vlc/plugins
else
  # Windows (MinGW)
  OUTPUT = $(PLUGIN_NAME)_plugin.dll
  LDFLAGS += -shared -lvlccore
  INSTALL_DIR ?= $(APPDATA)/vlc/plugins
endif

.PHONY: all clean install uninstall

all: $(OUTPUT)

$(OUTPUT): scheduler.c
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

install: $(OUTPUT)
	@mkdir -p "$(INSTALL_DIR)"
	cp $(OUTPUT) "$(INSTALL_DIR)/$(OUTPUT)"
	@echo "Installed $(OUTPUT) to $(INSTALL_DIR)"

uninstall:
	rm -f "$(INSTALL_DIR)/$(OUTPUT)"
	@echo "Removed $(OUTPUT) from $(INSTALL_DIR)"

clean:
	rm -f $(OUTPUT) lib$(PLUGIN_NAME)_plugin.dylib lib$(PLUGIN_NAME)_plugin.so $(PLUGIN_NAME)_plugin.dll
