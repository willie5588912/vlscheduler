/**
 * Minimal VLC 3.x stub: vlc_interface.h
 * For out-of-tree compilation only — NOT a real VLC header.
 */
#ifndef VLC_INTERFACE_H
#define VLC_INTERFACE_H

#include <vlc_common.h>

/* Forward-declare intf_sys_t (defined by each module) */
typedef struct intf_sys_t intf_sys_t;

/* Interface thread */
typedef struct intf_thread_t {
    vlc_object_t obj;
    intf_sys_t  *p_sys;
} intf_thread_t;

#endif /* VLC_INTERFACE_H */
