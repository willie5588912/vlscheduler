/**
 * Minimal VLC 3.x stub: vlc_input.h
 * For out-of-tree compilation only — NOT a real VLC header.
 */
#ifndef VLC_INPUT_H
#define VLC_INPUT_H

#include <vlc_common.h>

/* Video output thread */
typedef struct vout_thread_t {
    vlc_object_t obj;
} vout_thread_t;

/* Input thread */
typedef struct input_thread_t {
    vlc_object_t obj;
} input_thread_t;

/* Get the video output from an input thread */
static inline vout_thread_t *input_GetVout(input_thread_t *input)
{ (void)input; return NULL; }

#endif /* VLC_INPUT_H */
