/**
 * Minimal VLC 3.x stub: vlc_threads.h
 * For out-of-tree compilation only — NOT a real VLC header.
 */
#ifndef VLC_THREADS_H
#define VLC_THREADS_H

#include <vlc_common.h>

/* Timer handle (opaque pointer) */
typedef struct vlc_timer *vlc_timer_t;

static inline int vlc_timer_create(vlc_timer_t *timer,
                                   void (*callback)(void *), void *data)
{ (void)timer; (void)callback; (void)data; return 0; }

static inline void vlc_timer_destroy(vlc_timer_t timer)
{ (void)timer; }

static inline void vlc_timer_schedule(vlc_timer_t timer, bool absolute,
                                      vlc_tick_t value, vlc_tick_t interval)
{ (void)timer; (void)absolute; (void)value; (void)interval; }

#endif /* VLC_THREADS_H */
