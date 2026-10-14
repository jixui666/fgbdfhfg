// neutralizer_log.m — sandbox-visible logging for the neutralizer shim.
//
// Pure C implementation (no Foundation dependency at construction time):
// every line is appended to ALL writable candidates:
//   1. $HOME/Documents/neutralizer.log   (app data container)
//   2. /var/mobile/Documents/neutralizer.log
//   3. /tmp/neutralizer.log
// and mirrored to NSLog (os_log / Console).
#import <Foundation/Foundation.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "neutralizer_log.h"

#define NZ_MAX_FILES 8
#define NZ_MAX_TRACKED 512   // enough for the 254-symbol spec
#define NZ_FLUSH_EVERY 32    // write the running total every N hits

static pthread_mutex_t s_lock = PTHREAD_MUTEX_INITIALIZER;
static FILE *s_files[NZ_MAX_FILES];
static int s_file_count = 0;
static long long s_total_hits = 0;
static const char *s_seen[NZ_MAX_TRACKED];
static int s_seen_count = 0;

static void open_candidate(const char *path)
{
    if (s_file_count >= NZ_MAX_FILES) return;
    FILE *f = fopen(path, "ab");
    if (f) {
        s_files[s_file_count++] = f;
        char line[512];
        snprintf(line, sizeof(line), "neutralizer log opened: %s", path);
        fputs(line, f);
        fputc('\n', f);
        fflush(f);
    }
}

static void ensure_files(void)
{
    if (s_file_count > 0) return;
    const char *home = getenv("HOME");
    if (home && *home) {
        char path[1024];
        snprintf(path, sizeof(path), "%s/Documents/neutralizer.log", home);
        open_candidate(path);
    }
    open_candidate("/var/mobile/Documents/neutralizer.log");
    open_candidate("/tmp/neutralizer.log");
}

static void write_line(const char *line)
{
    for (int i = 0; i < s_file_count; i++) {
        fputs(line, s_files[i]);
        fputc('\n', s_files[i]);
        fflush(s_files[i]);
    }
}

void nz_log(const char *fmt, ...)
{
    pthread_mutex_lock(&s_lock);

    time_t now = time(NULL);
    struct tm tm_now;
    localtime_r(&now, &tm_now);
    char stamp[32];
    strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &tm_now);

    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    ensure_files();
    char line[2048];
    snprintf(line, sizeof(line), "[%s] %s", stamp, buf);
    write_line(line);
    NSLog(@"[neutralizer] %s", buf);

    pthread_mutex_unlock(&s_lock);
}

void nz_log_stub_hit(const char *name)
{
    pthread_mutex_lock(&s_lock);
    s_total_hits++;
    int is_new = 0;
    if (s_seen_count < NZ_MAX_TRACKED) {
        int i;
        for (i = 0; i < s_seen_count; i++) {
            if (strcmp(s_seen[i], name) == 0) break;
        }
        if (i == s_seen_count) {
            s_seen[s_seen_count++] = name;
            is_new = 1;
        }
    }
    time_t now = time(NULL);
    struct tm tm_now;
    localtime_r(&now, &tm_now);
    char stamp[32];
    strftime(stamp, sizeof(stamp), "%H:%M:%S", &tm_now);

    char line[512];
    if (is_new) {
        snprintf(line, sizeof(line), "[%s] STUB-HIT(first) %s (total hits %lld)",
                 stamp, name, s_total_hits);
        ensure_files();
        write_line(line);
        NSLog(@"[neutralizer] STUB-HIT(first) %s", name);
    } else if ((s_total_hits % NZ_FLUSH_EVERY) == 0) {
        snprintf(line, sizeof(line), "[%s] stub total hits so far: %lld", stamp, s_total_hits);
        ensure_files();
        write_line(line);
    }
    pthread_mutex_unlock(&s_lock);
}
