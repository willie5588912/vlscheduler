/*****************************************************************************
 * scheduler.c: scheduled playlist playback interface module for VLC 3.x
 *****************************************************************************
 * Copyright (C) 2026 the VideoLAN team
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/**
 * VLC Scheduler Plugin (VLC 3.x)
 *
 * Automatically plays playlists at scheduled times on specific weekdays.
 * Configure via a simple text file:
 *
 *   MON  22:30  /path/to/monday.m3u
 *   TUE  22:30  /path/to/tuesday.m3u
 *
 * Usage:
 *   vlc --extraintf scheduler --scheduler-config /path/to/schedule.conf
 */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <time.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* For out-of-tree builds, N_() may not be available */
#ifndef N_
# define N_(str) (str)
#endif

#define VLC_MODULE_LICENSE VLC_LICENSE_GPL_2_PLUS
#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_interface.h>
#include <vlc_playlist.h>
#include <vlc_input.h>
#include <vlc_input_item.h>
#include <vlc_url.h>
#include <vlc_threads.h>

/*****************************************************************************
 * Constants
 *****************************************************************************/
#define SCHED_MAX_ENTRIES 64
#define SCHED_MAX_PATH    512
#define SCHED_POLL_SEC    30

/*****************************************************************************
 * Data structures
 *****************************************************************************/
struct sched_entry
{
    int  day;                       /* 0=Sun, 1=Mon, ..., 6=Sat (tm_wday) */
    int  hour;                      /* 0-23 */
    int  minute;                    /* 0-59 */
    char path[SCHED_MAX_PATH];     /* path to M3U playlist file */
};

struct intf_sys_t
{
    playlist_t        *playlist;
    vlc_timer_t        timer;
    bool               fullscreen;

    struct sched_entry entries[SCHED_MAX_ENTRIES];
    int                entry_count;

    /* De-duplication: prevent re-triggering within same minute */
    int                last_triggered_day;
    int                last_triggered_hour;
    int                last_triggered_minute;
};

/*****************************************************************************
 * Forward declarations
 *****************************************************************************/
static int  Open(vlc_object_t *);
static void Close(vlc_object_t *);
static void TimerCallback(void *);
static int  ParseConfig(intf_thread_t *, const char *);
static int  DayFromString(const char *);
static int  LoadM3U(intf_thread_t *, const char *);

/*****************************************************************************
 * DayFromString: convert 3-letter day abbreviation to tm_wday value
 *****************************************************************************/
static int DayFromString(const char *str)
{
    static const char *days[] = {
        "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"
    };

    for (int i = 0; i < 7; i++)
    {
        if (strncasecmp(str, days[i], 3) == 0)
            return i;
    }
    return -1;
}

/*****************************************************************************
 * ParseConfig: read and parse the schedule configuration file
 *****************************************************************************/
static int ParseConfig(intf_thread_t *intf, const char *path)
{
    intf_sys_t *sys = intf->p_sys;
    sys->entry_count = 0;

    FILE *fp = fopen(path, "r");
    if (fp == NULL)
    {
        msg_Err(intf, "scheduler: cannot open config file '%s'", path);
        return VLC_EGENERIC;
    }

    char line[1024];
    int lineno = 0;

    while (fgets(line, sizeof(line), fp) != NULL)
    {
        lineno++;

        /* Strip trailing newline/carriage return */
        char *nl = strchr(line, '\n');
        if (nl) *nl = '\0';
        nl = strchr(line, '\r');
        if (nl) *nl = '\0';

        /* Skip leading whitespace */
        const char *p = line;
        while (*p == ' ' || *p == '\t') p++;

        /* Skip empty lines and comments */
        if (*p == '\0' || *p == '#')
            continue;

        /* Parse: DAY  HH:MM  PATH */
        char day_str[8];
        int hour, minute;
        char m3u_path[SCHED_MAX_PATH];

        int matched = sscanf(p, "%7s %d:%d %511[^\n]",
                             day_str, &hour, &minute, m3u_path);
        if (matched != 4)
        {
            msg_Warn(intf, "scheduler: skipping malformed line %d", lineno);
            continue;
        }

        int day = DayFromString(day_str);
        if (day < 0)
        {
            msg_Warn(intf, "scheduler: unknown day '%s' on line %d",
                     day_str, lineno);
            continue;
        }

        if (hour < 0 || hour > 23 || minute < 0 || minute > 59)
        {
            msg_Warn(intf, "scheduler: invalid time %d:%02d on line %d",
                     hour, minute, lineno);
            continue;
        }

        if (sys->entry_count >= SCHED_MAX_ENTRIES)
        {
            msg_Warn(intf, "scheduler: max entries (%d) reached, ignoring rest",
                     SCHED_MAX_ENTRIES);
            break;
        }

        struct sched_entry *e = &sys->entries[sys->entry_count];
        e->day    = day;
        e->hour   = hour;
        e->minute = minute;

        /* Trim leading whitespace from path */
        const char *pp = m3u_path;
        while (*pp == ' ' || *pp == '\t') pp++;
        strncpy(e->path, pp, SCHED_MAX_PATH - 1);
        e->path[SCHED_MAX_PATH - 1] = '\0';

        /* Trim trailing whitespace from path */
        size_t len = strlen(e->path);
        while (len > 0 && (e->path[len - 1] == ' ' || e->path[len - 1] == '\t'))
            e->path[--len] = '\0';

        msg_Dbg(intf, "scheduler: entry %d: day=%d time=%02d:%02d path=%s",
                sys->entry_count, day, hour, minute, e->path);
        sys->entry_count++;
    }

    fclose(fp);

    if (sys->entry_count == 0)
    {
        msg_Warn(intf, "scheduler: no valid entries found in '%s'", path);
        return VLC_EGENERIC;
    }

    msg_Info(intf, "scheduler: loaded %d schedule entries", sys->entry_count);
    return VLC_SUCCESS;
}

/*****************************************************************************
 * LoadM3U: parse an M3U file and load its entries into the VLC playlist
 *****************************************************************************/
static int LoadM3U(intf_thread_t *intf, const char *path)
{
    intf_sys_t *sys = intf->p_sys;

    FILE *fp = fopen(path, "r");
    if (fp == NULL)
    {
        msg_Err(intf, "scheduler: cannot open M3U file '%s'", path);
        return VLC_EGENERIC;
    }

    /*
     * First pass: collect valid file paths/URIs into a heap buffer.
     * We do file I/O outside the playlist lock to minimize lock hold time.
     */
    char **lines = NULL;
    int line_count = 0;
    int line_capacity = 0;
    char buf[SCHED_MAX_PATH];

    while (fgets(buf, sizeof(buf), fp) != NULL)
    {
        /* Strip newlines */
        char *nl = strchr(buf, '\n');
        if (nl) *nl = '\0';
        nl = strchr(buf, '\r');
        if (nl) *nl = '\0';

        /* Skip blank lines and comments/extended M3U directives */
        const char *p = buf;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '\0' || *p == '#')
            continue;

        /* Grow array if needed */
        if (line_count >= line_capacity)
        {
            int new_cap = line_capacity == 0 ? 64 : line_capacity * 2;
            char **new_lines = realloc(lines, sizeof(char *) * new_cap);
            if (new_lines == NULL)
            {
                msg_Err(intf, "scheduler: out of memory reading M3U");
                break;
            }
            lines = new_lines;
            line_capacity = new_cap;
        }

        lines[line_count] = strdup(p);
        if (lines[line_count] == NULL)
        {
            msg_Err(intf, "scheduler: out of memory reading M3U");
            break;
        }
        line_count++;
    }
    fclose(fp);

    if (line_count == 0)
    {
        msg_Warn(intf, "scheduler: M3U file '%s' contains no entries", path);
        free(lines);
        return VLC_EGENERIC;
    }

    /*
     * VLC 3.x playlist API:
     *   Note: playlist_AddInput() locks internally, so we must NOT hold
     *   the playlist lock when calling it. Use unlocked variants for
     *   stop/clear/play as well.
     */
    playlist_Stop(sys->playlist);
    playlist_Clear(sys->playlist, false);  /* false = not locked */

    int count = 0;
    for (int i = 0; i < line_count; i++)
    {
        char *uri;

        /* Check if the line is already a URI (contains "://") */
        if (strstr(lines[i], "://") != NULL)
            uri = strdup(lines[i]);
        else
            uri = vlc_path2uri(lines[i], NULL);

        if (uri == NULL)
        {
            msg_Warn(intf, "scheduler: failed to convert '%s' to URI",
                     lines[i]);
            continue;
        }

        input_item_t *item = input_item_New(uri, NULL);
        free(uri);

        if (item == NULL)
        {
            msg_Warn(intf, "scheduler: failed to create input item for '%s'",
                     lines[i]);
            continue;
        }

        /* playlist_AddInput(playlist, item, play_now, b_playlist)
         * - play_now=false: don't start playing immediately
         * - b_playlist=true: add to "Playlist" tree (not media library)
         * This function locks the playlist internally. */
        if (playlist_AddInput(sys->playlist, item, false, true) == VLC_SUCCESS)
            count++;
        else
            msg_Warn(intf, "scheduler: failed to insert '%s'", lines[i]);

        input_item_Release(item);
    }

    if (count > 0)
    {
        playlist_Play(sys->playlist);
        msg_Info(intf, "scheduler: started playback with %d items from '%s'",
                 count, path);
    }
    else
    {
        msg_Warn(intf, "scheduler: no items were loaded from '%s'", path);
    }

    /* Free the lines buffer */
    for (int i = 0; i < line_count; i++)
        free(lines[i]);
    free(lines);

    return (count > 0) ? VLC_SUCCESS : VLC_EGENERIC;
}

/*****************************************************************************
 * TimerCallback: called every SCHED_POLL_SEC seconds
 *****************************************************************************/
static void TimerCallback(void *data)
{
    intf_thread_t *intf = (intf_thread_t *)data;
    intf_sys_t *sys = intf->p_sys;

    /* Get current wall-clock time */
    time_t now = time(NULL);
    struct tm tm_now;
#ifdef _WIN32
    localtime_s(&tm_now, &now);
#else
    localtime_r(&now, &tm_now);
#endif

    int cur_wday = tm_now.tm_wday;    /* 0=Sunday ... 6=Saturday */
    int cur_hour = tm_now.tm_hour;
    int cur_min  = tm_now.tm_min;

    /* Check against each schedule entry */
    for (int i = 0; i < sys->entry_count; i++)
    {
        struct sched_entry *e = &sys->entries[i];

        if (e->day != cur_wday || e->hour != cur_hour || e->minute != cur_min)
            continue;

        /* Match found — check de-duplication */
        if (sys->last_triggered_day    == cur_wday &&
            sys->last_triggered_hour   == cur_hour &&
            sys->last_triggered_minute == cur_min)
        {
            return;  /* Already triggered for this minute */
        }

        msg_Info(intf, "scheduler: trigger! day=%d time=%02d:%02d -> %s",
                 cur_wday, cur_hour, cur_min, e->path);

        /* Record trigger to prevent re-fire */
        sys->last_triggered_day    = cur_wday;
        sys->last_triggered_hour   = cur_hour;
        sys->last_triggered_minute = cur_min;

        /* Load the M3U and start playback */
        if (LoadM3U(intf, e->path) == VLC_SUCCESS && sys->fullscreen)
        {
            /*
             * VLC 3.x fullscreen: set on both playlist and vout.
             * The playlist variable is inherited by future vouts,
             * so this works even before the video output is created.
             * (Same pattern as hotkeys.c)
             */
            var_SetBool(sys->playlist, "fullscreen", true);

            input_thread_t *p_input = playlist_CurrentInput(sys->playlist);
            if (p_input != NULL)
            {
                vout_thread_t *p_vout = input_GetVout(p_input);
                if (p_vout != NULL)
                {
                    var_SetBool(p_vout, "fullscreen", true);
                    vlc_object_release(p_vout);
                }
                vlc_object_release(p_input);
            }
        }

        return;  /* Only trigger one schedule per timer tick */
    }
}

/*****************************************************************************
 * Open: module activation
 *****************************************************************************/
static int Open(vlc_object_t *obj)
{
    intf_thread_t *intf = (intf_thread_t *)obj;

    /* Read the config file path */
    char *config_path = var_InheritString(intf, "scheduler-config");
    if (config_path == NULL || config_path[0] == '\0')
    {
        msg_Err(intf, "scheduler: no config file specified "
                      "(set --scheduler-config)");
        free(config_path);
        return VLC_EGENERIC;
    }

    /* Allocate system data */
    intf_sys_t *sys = malloc(sizeof(*sys));
    if (sys == NULL)
    {
        free(config_path);
        return VLC_ENOMEM;
    }

    /* VLC 3.x: get playlist via pl_Get() */
    sys->playlist   = pl_Get(intf);
    sys->fullscreen = var_InheritBool(intf, "scheduler-fullscreen");
    sys->entry_count = 0;
    sys->last_triggered_day    = -1;
    sys->last_triggered_hour   = -1;
    sys->last_triggered_minute = -1;

    intf->p_sys = sys;

    /* Parse configuration file */
    if (ParseConfig(intf, config_path) != VLC_SUCCESS)
    {
        msg_Err(intf, "scheduler: failed to parse config '%s'", config_path);
        free(config_path);
        free(sys);
        intf->p_sys = NULL;
        return VLC_EGENERIC;
    }
    free(config_path);

    /* Create the polling timer */
    if (vlc_timer_create(&sys->timer, TimerCallback, intf) != 0)
    {
        msg_Err(intf, "scheduler: failed to create timer");
        free(sys);
        intf->p_sys = NULL;
        return VLC_EGENERIC;
    }

    /* Fire in 1 tick, then repeat every SCHED_POLL_SEC seconds */
    vlc_timer_schedule(sys->timer, false, 1, VLC_TICK_FROM_SEC(SCHED_POLL_SEC));

    msg_Info(intf, "scheduler: started with %d entries, polling every %ds",
             sys->entry_count, SCHED_POLL_SEC);
    return VLC_SUCCESS;
}

/*****************************************************************************
 * Close: module deactivation
 *****************************************************************************/
static void Close(vlc_object_t *obj)
{
    intf_thread_t *intf = (intf_thread_t *)obj;
    intf_sys_t *sys = intf->p_sys;

    /* vlc_timer_destroy disarms the timer and waits for any
     * running callback to complete before returning. */
    vlc_timer_destroy(sys->timer);

    msg_Info(intf, "scheduler: stopped");
    free(sys);
}

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/
vlc_module_begin()
    set_shortname(N_("Scheduler"))
    set_description(N_("Scheduled playlist playback"))
    set_capability("interface", 0)
    set_callbacks(Open, Close)
    set_category(CAT_INTERFACE)
    set_subcategory(SUBCAT_INTERFACE_CONTROL)

    add_string("scheduler-config", "",
               N_("Schedule config file"),
               N_("Path to the schedule configuration file. "
                  "Format: DAY HH:MM /path/to/playlist.m3u"),
               false)
    add_bool("scheduler-fullscreen", false,
             N_("Fullscreen on schedule"),
             N_("Switch to fullscreen when a scheduled playlist starts"),
             false)
vlc_module_end()
