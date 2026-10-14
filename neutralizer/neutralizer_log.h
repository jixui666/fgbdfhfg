// neutralizer_log.h — sandbox-visible logging for the neutralizer shim.
#ifndef NEUTRALIZER_LOG_H
#define NEUTRALIZER_LOG_H

#ifdef __cplusplus
extern "C" {
#endif

// Append a timestamped line to <app sandbox>/Documents/neutralizer.log and
// mirror it to NSLog.
void nz_log(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

// Called by every generated stub on each invocation. Logs the first hit per
// symbol (proof that the call was redirected into our dylib) and keeps a
// total counter that is flushed periodically.
void nz_log_stub_hit(const char *name);

#ifdef __cplusplus
}
#endif

#endif // NEUTRALIZER_LOG_H
