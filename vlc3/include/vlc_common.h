/**
 * Minimal VLC 3.x stub: vlc_common.h
 * For out-of-tree compilation only — NOT a real VLC header.
 */
#ifndef VLC_COMMON_H
#define VLC_COMMON_H

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

/* License token used by VLC_MODULE_LICENSE */
#define VLC_LICENSE_GPL_2_PLUS

/* Return codes */
#define VLC_SUCCESS   0
#define VLC_EGENERIC  (-1)
#define VLC_ENOMEM    (-2)

/* Gettext stub */
#ifndef N_
# define N_(str) (str)
#endif

/* Tick type (VLC uses int64_t microseconds) */
typedef int64_t vlc_tick_t;
#define VLC_TICK_FROM_SEC(s) ((vlc_tick_t)(s) * INT64_C(1000000))

/* Base VLC object */
typedef struct vlc_object_t {
    void *dummy;
} vlc_object_t;

/* Logging macros (no-op stubs) */
#define msg_Err(obj, ...)   ((void)(obj))
#define msg_Warn(obj, ...)  ((void)(obj))
#define msg_Info(obj, ...)  ((void)(obj))
#define msg_Dbg(obj, ...)   ((void)(obj))

/* Variable helpers */
static inline char *var_InheritString(void *obj, const char *name)
{ (void)obj; (void)name; return NULL; }

static inline bool var_InheritBool(void *obj, const char *name)
{ (void)obj; (void)name; return false; }

static inline void var_SetBool(void *obj, const char *name, bool val)
{ (void)obj; (void)name; (void)val; }

/* Object release */
static inline void vlc_object_release(void *obj)
{ (void)obj; }

#endif /* VLC_COMMON_H */
