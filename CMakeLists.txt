cmake_minimum_required(VERSION 3.10)
project(vlscheduler VERSION 0.0.1 LANGUAGES C)

# --------------------------------------------------------------------------
# Options
# --------------------------------------------------------------------------
set(VLC_INCLUDE_DIR "" CACHE PATH "Path to VLC 3.x SDK include directory")
set(VLC_LIB_DIR     "" CACHE PATH "Path to VLC 3.x SDK lib directory (Windows)")

# --------------------------------------------------------------------------
# Auto-detect VLC include path if not set
# --------------------------------------------------------------------------
if(NOT VLC_INCLUDE_DIR OR VLC_INCLUDE_DIR STREQUAL "")
    # Check common locations
    if(EXISTS "${CMAKE_SOURCE_DIR}/vlc3/include")
        set(VLC_INCLUDE_DIR "${CMAKE_SOURCE_DIR}/vlc3/include")
    elseif(WIN32)
        # Common VLC install locations on Windows
        set(_vlc_candidates
            "$ENV{ProgramFiles}/VideoLAN/VLC/sdk/include"
            "$ENV{ProgramFiles\(x86\)}/VideoLAN/VLC/sdk/include"
            "C:/Program Files/VideoLAN/VLC/sdk/include"
        )
        foreach(_dir ${_vlc_candidates})
            if(EXISTS "${_dir}")
                set(VLC_INCLUDE_DIR "${_dir}")
                break()
            endif()
        endforeach()
    elseif(APPLE)
        if(EXISTS "/Applications/VLC.app/Contents/MacOS/include")
            set(VLC_INCLUDE_DIR "/Applications/VLC.app/Contents/MacOS/include")
        endif()
    else()
        # Linux: try pkg-config
        find_package(PkgConfig QUIET)
        if(PKG_CONFIG_FOUND)
            pkg_check_modules(VLC QUIET vlc-plugin)
            if(VLC_FOUND)
                set(VLC_INCLUDE_DIR "${VLC_INCLUDE_DIRS}")
            endif()
        endif()
        if(NOT VLC_INCLUDE_DIR)
            set(VLC_INCLUDE_DIR "/usr/include/vlc/plugins")
        endif()
    endif()
endif()

message(STATUS "VLC include dir: ${VLC_INCLUDE_DIR}")

# --------------------------------------------------------------------------
# Plugin target
# --------------------------------------------------------------------------
set(PLUGIN_NAME scheduler)

add_library(${PLUGIN_NAME}_plugin MODULE scheduler.c)

target_include_directories(${PLUGIN_NAME}_plugin PRIVATE "${VLC_INCLUDE_DIR}")

target_compile_definitions(${PLUGIN_NAME}_plugin PRIVATE
    __PLUGIN__
    MODULE_STRING="${PLUGIN_NAME}"
    _FILE_OFFSET_BITS=64
)

if(MSVC)
    target_compile_options(${PLUGIN_NAME}_plugin PRIVATE /W3 /O2)
else()
    target_compile_options(${PLUGIN_NAME}_plugin PRIVATE -Wall -Wextra -O2)
    set_target_properties(${PLUGIN_NAME}_plugin PROPERTIES
        POSITION_INDEPENDENT_CODE ON
    )
endif()

# Platform-specific linking
if(WIN32)
    # On Windows, we must link against vlccore
    if(VLC_LIB_DIR AND NOT VLC_LIB_DIR STREQUAL "")
        target_link_directories(${PLUGIN_NAME}_plugin PRIVATE "${VLC_LIB_DIR}")
    elseif(EXISTS "$ENV{ProgramFiles}/VideoLAN/VLC/sdk/lib")
        target_link_directories(${PLUGIN_NAME}_plugin PRIVATE
            "$ENV{ProgramFiles}/VideoLAN/VLC/sdk/lib"
        )
    endif()
    target_link_libraries(${PLUGIN_NAME}_plugin PRIVATE vlccore)

    # Output name without "lib" prefix on Windows
    set_target_properties(${PLUGIN_NAME}_plugin PROPERTIES PREFIX "")
elseif(APPLE)
    # macOS: allow undefined symbols (resolved at load time by VLC)
    set_target_properties(${PLUGIN_NAME}_plugin PROPERTIES
        LINK_FLAGS "-undefined dynamic_lookup"
        SUFFIX ".dylib"
        PREFIX "lib"
    )
else()
    # Linux
    set_target_properties(${PLUGIN_NAME}_plugin PROPERTIES
        PREFIX "lib"
    )
endif()

# --------------------------------------------------------------------------
# Install targets
# --------------------------------------------------------------------------
if(WIN32)
    set(DEFAULT_PLUGIN_DIR "$ENV{APPDATA}/vlc/plugins")
    set(DEFAULT_EXT_DIR    "$ENV{APPDATA}/vlc/lua/extensions")
elseif(APPLE)
    set(DEFAULT_PLUGIN_DIR "$ENV{HOME}/Library/Application Support/org.videolan.vlc/plugins")
    set(DEFAULT_EXT_DIR    "/Applications/VLC.app/Contents/MacOS/share/lua/extensions")
else()
    set(DEFAULT_PLUGIN_DIR "$ENV{HOME}/.local/share/vlc/plugins")
    set(DEFAULT_EXT_DIR    "$ENV{HOME}/.local/share/vlc/lua/extensions")
endif()

set(PLUGIN_INSTALL_DIR "${DEFAULT_PLUGIN_DIR}" CACHE PATH "VLC plugin install directory")
set(EXT_INSTALL_DIR    "${DEFAULT_EXT_DIR}"    CACHE PATH "VLC Lua extension install directory")

install(TARGETS ${PLUGIN_NAME}_plugin LIBRARY DESTINATION "${PLUGIN_INSTALL_DIR}")
install(FILES vlscheduler.lua DESTINATION "${EXT_INSTALL_DIR}")

message(STATUS "Plugin will install to: ${PLUGIN_INSTALL_DIR}")
message(STATUS "Extension will install to: ${EXT_INSTALL_DIR}")
