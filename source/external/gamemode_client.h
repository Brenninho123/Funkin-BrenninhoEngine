#ifndef CLIENT_GAMEMODE_H
#define CLIENT_GAMEMODE_H

#include <stdbool.h>
#include <stdio.h>
#include <dlfcn.h>
#include <string.h>
#include <assert.h>
#include <sys/types.h>

#define GAMEMODE_ERROR_LEN 512

typedef int          (*gamemode_fn_void)(void);
typedef const char * (*gamemode_fn_str)(void);
typedef int          (*gamemode_fn_pid)(pid_t);

typedef struct {
    const char  *name;
    void       **functor;
    size_t       func_size;
    bool         required;
} gamemode_binding_t;

static char     gm_error_buf[GAMEMODE_ERROR_LEN] = { 0 };
static volatile int gm_loaded                    = 1;
static void    *gm_handle                        = NULL;

static gamemode_fn_void gm_request_start     = NULL;
static gamemode_fn_void gm_request_end       = NULL;
static gamemode_fn_void gm_query_status      = NULL;
static gamemode_fn_str  gm_error_string_fn   = NULL;
static gamemode_fn_pid  gm_request_start_for = NULL;
static gamemode_fn_pid  gm_request_end_for   = NULL;
static gamemode_fn_pid  gm_query_status_for  = NULL;

__attribute__((always_inline))
static inline void gm_set_error(const char *fmt, const char *detail)
{
    snprintf(gm_error_buf, GAMEMODE_ERROR_LEN, fmt, detail ? detail : "unknown");
}

__attribute__((always_inline))
static inline int gm_bind_symbol(void *handle, const char *name, void **out, size_t size, bool required)
{
    dlerror();
    void  *sym = dlsym(handle, name);
    char  *err = dlerror();

    if (required && (err || !sym)) {
        gm_set_error("dlsym failed - %s", err);
        return -1;
    }

    if (sym)
        memcpy(out, &sym, size);

    return 0;
}

__attribute__((always_inline))
static inline int gm_load(void)
{
    if (gm_loaded != 1)
        return gm_loaded;

    gm_handle = dlopen("libgamemode.so.0", RTLD_NOW);
    if (!gm_handle)
        gm_handle = dlopen("libgamemode.so", RTLD_NOW);

    if (!gm_handle) {
        gm_set_error("dlopen failed - %s", dlerror());
        gm_loaded = -1;
        return -1;
    }

    gamemode_binding_t bindings[] = {
        { "real_gamemode_request_start",     (void **)&gm_request_start,     sizeof(gm_request_start),     true  },
        { "real_gamemode_request_end",       (void **)&gm_request_end,       sizeof(gm_request_end),       true  },
        { "real_gamemode_query_status",      (void **)&gm_query_status,      sizeof(gm_query_status),      false },
        { "real_gamemode_error_string",      (void **)&gm_error_string_fn,   sizeof(gm_error_string_fn),   true  },
        { "real_gamemode_request_start_for", (void **)&gm_request_start_for, sizeof(gm_request_start_for), false },
        { "real_gamemode_request_end_for",   (void **)&gm_request_end_for,   sizeof(gm_request_end_for),   false },
        { "real_gamemode_query_status_for",  (void **)&gm_query_status_for,  sizeof(gm_query_status_for),  false },
    };

    size_t count = sizeof(bindings) / sizeof(bindings[0]);
    for (size_t i = 0; i < count; i++) {
        gamemode_binding_t *b = &bindings[i];
        if (gm_bind_symbol(gm_handle, b->name, b->functor, b->func_size, b->required) < 0) {
            gm_loaded = -1;
            return -1;
        }
    }

    gm_loaded = 0;
    return 0;
}

__attribute__((always_inline))
static inline const char *gamemode_error_string(void)
{
    if (gm_load() < 0 || gm_error_buf[0] != '\0')
        return gm_error_buf;

    assert(gm_error_string_fn != NULL);
    return gm_error_string_fn();
}

#define GM_MISSING(fname) \
    gm_set_error(fname " missing (older host?)", NULL); \
    return -1;

#ifdef GAMEMODE_AUTO
__attribute__((constructor))
#else
__attribute__((always_inline)) static inline
#endif
int gamemode_request_start(void)
{
    if (gm_load() < 0) {
#ifdef GAMEMODE_AUTO
        fprintf(stderr, "gamemodeauto: %s\n", gamemode_error_string());
#endif
        return -1;
    }

    assert(gm_request_start != NULL);

    if (gm_request_start() < 0) {
#ifdef GAMEMODE_AUTO
        fprintf(stderr, "gamemodeauto: %s\n", gamemode_error_string());
#endif
        return -1;
    }

    return 0;
}

#ifdef GAMEMODE_AUTO
__attribute__((destructor))
#else
__attribute__((always_inline)) static inline
#endif
int gamemode_request_end(void)
{
    if (gm_load() < 0) {
#ifdef GAMEMODE_AUTO
        fprintf(stderr, "gamemodeauto: %s\n", gamemode_error_string());
#endif
        return -1;
    }

    assert(gm_request_end != NULL);

    if (gm_request_end() < 0) {
#ifdef GAMEMODE_AUTO
        fprintf(stderr, "gamemodeauto: %s\n", gamemode_error_string());
#endif
        return -1;
    }

    return 0;
}

__attribute__((always_inline))
static inline int gamemode_query_status(void)
{
    if (gm_load() < 0)
        return -1;

    if (!gm_query_status) {
        GM_MISSING("gamemode_query_status");
    }

    return ((gamemode_fn_void)gm_query_status)();
}

__attribute__((always_inline))
static inline int gamemode_request_start_for(pid_t pid)
{
    if (gm_load() < 0)
        return -1;

    if (!gm_request_start_for) {
        GM_MISSING("gamemode_request_start_for");
    }

    return gm_request_start_for(pid);
}

__attribute__((always_inline))
static inline int gamemode_request_end_for(pid_t pid)
{
    if (gm_load() < 0)
        return -1;

    if (!gm_request_end_for) {
        GM_MISSING("gamemode_request_end_for");
    }

    return gm_request_end_for(pid);
}

__attribute__((always_inline))
static inline int gamemode_query_status_for(pid_t pid)
{
    if (gm_load() < 0)
        return -1;

    if (!gm_query_status_for) {
        GM_MISSING("gamemode_query_status_for");
    }

    return gm_query_status_for(pid);
}

#undef GM_MISSING

#endif
