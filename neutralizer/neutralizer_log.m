// neutralizer_log.m — sandbox-visible logging implementation.
//
// Log file: <app container>/Documents/neutralizer.log  (append mode).
// Mirror every line to NSLog as well.
#import <Foundation/Foundation.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "neutralizer_log.h"

#define NZ_MAX_TRACKED 512   // enough for the 254-symbol spec
#define NZ_FLUSH_EVERY 32    // write the running total every N hits

static NSLock *s_lock = nil;
static FILE *s_file = NULL;
static long long s_total_hits = 0;
static const char *s_seen[NZ_MAX_TRACKED];
static int s_seen_count = 0;

static void ensure_file(void)
{
    if (s_file) return;
    @autoreleasepool {
        NSArray<NSString *> *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                        NSUserDomainMask, YES);
        NSString *dir = dirs.count ? dirs.firstObject : NSTemporaryDirectory();
        NSString *path = [dir stringByAppendingPathComponent:@"neutralizer.log"];
        s_file = fopen(path.fileSystemRepresentation, "ab");
    }
}

static void write_line(const char *line)
{
    if (!s_file) return;
    fputs(line, s_file);
    fputc('\n', s_file);
    fflush(s_file);
}

void nz_log(const char *fmt, ...)
{
    if (!s_lock) s_lock = [NSLock new];
    [s_lock lock];
    @autoreleasepool {
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

        ensure_file();
        char line[2048];
        snprintf(line, sizeof(line), "[%s] %s", stamp, buf);
        write_line(line);
        NSLog(@"[neutralizer] %s", buf);
    }
    [s_lock unlock];
}

void nz_log_stub_hit(const char *name)
{
    if (!s_lock) s_lock = [NSLock new];
    [s_lock lock];
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
    @autoreleasepool {
        time_t now = time(NULL);
        struct tm tm_now;
        localtime_r(&now, &tm_now);
        char stamp[32];
        strftime(stamp, sizeof(stamp), "%H:%M:%S", &tm_now);

        char line[512];
        if (is_new) {
            snprintf(line, sizeof(line), "[%s] STUB-HIT(first) %s (total hits %lld)",
                     stamp, name, s_total_hits);
            ensure_file();
            write_line(line);
            NSLog(@"[neutralizer] STUB-HIT(first) %s", name);
        } else if ((s_total_hits % NZ_FLUSH_EVERY) == 0) {
            snprintf(line, sizeof(line), "[%s] stub total hits so far: %lld", stamp, s_total_hits);
            ensure_file();
            write_line(line);
        }
    }
    [s_lock unlock];
}
