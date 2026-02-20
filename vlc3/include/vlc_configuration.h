/**
 * Minimal VLC 3.x stub: vlc_configuration.h
 * For out-of-tree compilation only — NOT a real VLC header.
 */
#ifndef VLC_CONFIGURATION_H
#define VLC_CONFIGURATION_H

#include <vlc_common.h>

/* User directory types */
#define VLC_DATA_DIR 0

static inline char *config_GetUserDir(int type)
{ (void)type; return NULL; }

#endif /* VLC_CONFIGURATION_H */
