/**
 * Minimal VLC 3.x stub: vlc_playlist.h
 * For out-of-tree compilation only — NOT a real VLC header.
 */
#ifndef VLC_PLAYLIST_H
#define VLC_PLAYLIST_H

#include <vlc_common.h>
#include <vlc_input_item.h>

/* Opaque playlist type */
typedef struct playlist_t {
    vlc_object_t obj;
} playlist_t;

/* Forward declarations for input types */
struct input_thread_t;

/* Playlist API stubs */
static inline void playlist_Stop(playlist_t *pl)
{ (void)pl; }

static inline void playlist_Clear(playlist_t *pl, bool locked)
{ (void)pl; (void)locked; }

static inline void playlist_Play(playlist_t *pl)
{ (void)pl; }

static inline int playlist_AddInput(playlist_t *pl, input_item_t *item,
                                    bool play, bool playlist_tree)
{ (void)pl; (void)item; (void)play; (void)playlist_tree; return VLC_SUCCESS; }

static inline struct input_thread_t *playlist_CurrentInput(playlist_t *pl)
{ (void)pl; return NULL; }

static inline playlist_t *pl_Get(void *obj)
{ (void)obj; return NULL; }

#endif /* VLC_PLAYLIST_H */
