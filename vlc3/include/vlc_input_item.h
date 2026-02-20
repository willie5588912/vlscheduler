/**
 * Minimal VLC 3.x stub: vlc_input_item.h
 * For out-of-tree compilation only — NOT a real VLC header.
 */
#ifndef VLC_INPUT_ITEM_H
#define VLC_INPUT_ITEM_H

#include <vlc_common.h>

/* Input item */
typedef struct input_item_t {
    void *dummy;
} input_item_t;

static inline input_item_t *input_item_New(const char *uri, const char *name)
{ (void)uri; (void)name; return NULL; }

static inline void input_item_Release(input_item_t *item)
{ (void)item; }

#endif /* VLC_INPUT_ITEM_H */
