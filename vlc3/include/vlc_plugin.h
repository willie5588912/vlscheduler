/**
 * Minimal VLC 3.x stub: vlc_plugin.h
 * For out-of-tree compilation only — NOT a real VLC header.
 */
#ifndef VLC_PLUGIN_H
#define VLC_PLUGIN_H

#include <vlc_common.h>

/* Category / subcategory constants */
#define CAT_INTERFACE           4
#define SUBCAT_INTERFACE_CONTROL 402

/* Module descriptor macros (expand to nothing for stub builds) */
#define vlc_module_begin()
#define vlc_module_end()
#define set_shortname(x)
#define set_description(x)
#define set_capability(cap, score)
#define set_callbacks(open, close)
#define set_category(x)
#define set_subcategory(x)
#define add_string(name, val, text, longtext, adv)
#define add_bool(name, val, text, longtext, adv)

#endif /* VLC_PLUGIN_H */
