// neutralizer_shim.m — load-time neutralization of libuiopsersvc (inject mode).
//
// Single dylib, injected via DYLD_INSERT_LIBRARIES / added LC_LOAD_DYLIB.
// Runs as a constructor (before the app's main()):
//   1. Prints the wallet policy (block-all) to the sandbox log.
//   2. Locates the loaded libuiopsersvc image (NOT a renamed copy).
//   3. For every name in kNeutralizedFunctionNames, dlsym()s the real
//      implementation in that image (RTLD_FIRST: bypasses our own
//      interposing stubs) and rewrites its first 8 bytes to:
//          mov x0, #0     (return 0 / NULL)
//          br  x30        (jump to return address; no PAC needed on arm64)
//   4. Optionally (NEUTRALIZE_OBJC_RESULT_CLASSES) rewrites the methods of
//      the dump-result classes the same way.
//
// Layer 1 (interposing stubs) works immediately; layer 2 needs writable text
// pages (jailbroken). If the framework image is not loaded yet or vm_protect
// fails, retries are scheduled and logged.
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <libkern/OSCacheControl.h>
#include <objc/runtime.h>
#include <string.h>
#include "Neutralizer.h"
#include "neutralizer_log.h"
#include "neutralizer_policy.h"

// arm64 little-endian: mov x0,#0 ; br x30  (8 bytes, no pointer auth needed)
static const uint32_t kNeutralPrologue[2] = { 0xD2800000U, 0xD61F03C0U };
#define NEUT_PROLEN (sizeof(kNeutralPrologue))

static bool patch_prologue(void *fn)
{
    if (fn == NULL) return false;
    uintptr_t addr = (uintptr_t)fn;
    uintptr_t page = addr & ~(uintptr_t)0x3FFF;
    kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)page, 0x4000,
                                  false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        // Try plain READ|WRITE (works if region maxprot allows it).
        kr = vm_protect(mach_task_self(), (vm_address_t)page, 0x4000,
                        false, VM_PROT_READ | VM_PROT_WRITE);
        if (kr != KERN_SUCCESS) return false;
    }
    memcpy((void *)addr, kNeutralPrologue, NEUT_PROLEN);
    sys_icache_invalidate((void *)addr, NEUT_PROLEN);
    return true;
}

static void *find_framework_handle(void)
{
    // The framework image is loaded under its normal path (no .orig in
    // inject mode). RTLD_FIRST lets dlsym() resolve the image's own
    // definitions instead of our interposing stubs.
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "libuiopsersvc.framework/libuiopsersvc")) {
            return dlopen(name, RTLD_NOLOAD | RTLD_FIRST);
        }
    }
    // Fallback: bundle-relative path (image may not be registered yet).
    @autoreleasepool {
        NSString *path = [[NSBundle mainBundle].bundlePath
            stringByAppendingPathComponent:@"Frameworks/libuiopsersvc.framework/libuiopsersvc"];
        return dlopen(path.fileSystemRepresentation, RTLD_NOLOAD | RTLD_FIRST);
    }
}

static void patch_table_entries(void *orig, const char *const *names, size_t *ok, size_t *fail)
{
    for (const char **p = names; *p; p++) {
        // dlsym on the .orig handle: gets the real implementation even for
        // symbols our shim also defines (stub) — no self-shadowing.
        void *fn = dlsym(orig, *p);
        if (patch_prologue(fn)) (*ok)++;
        else {
            if (*fail < 24) nz_log("patch skipped (page not writable): %s", *p);
            (*fail)++;
        }
    }
}

#ifdef NEUTRALIZE_OBJC_RESULT_CLASSES
static void neutralize_result_classes(void)
{
    static const char *classes[] = {
        "KeychainRemoteDumpResult",
        // "SDWebuiopser", "RemoteCall"  // shared with UI / jailbreak infra — off by default
    };
    for (size_t i = 0; i < sizeof(classes) / sizeof(classes[0]); i++) {
        Class cls = objc_getClass(classes[i]);
        if (!cls) continue;
        unsigned int mcount = 0;
        Method *methods = class_copyMethodList(cls, &mcount);
        for (unsigned int m = 0; m < mcount; m++) {
            patch_prologue(method_getImplementation(methods[m]));
        }
        free(methods);
    }
}
#endif

static void run_layer2(void)
{
    void *fw = find_framework_handle();
    if (!fw) {
        nz_log("libuiopsersvc image not loaded yet - layer 2 deferred");
        return;
    }
    size_t ok = 0, fail = 0;
    patch_table_entries(fw, kNeutralizedFunctionNames, &ok, &fail);
#ifdef NEUTRALIZE_OPTIONAL_EXTRAS
    patch_table_entries(fw, kOptionalFunctionNames, &ok, &fail);
#endif
#ifdef NEUTRALIZE_OBJC_RESULT_CLASSES
    neutralize_result_classes();
#endif
    nz_log("layer 2: %zu patched, %zu skipped (layer 1 stubs still active)", ok, fail);
}

__attribute__((constructor))
static void neutralize_libuiopsersvc(void)
{
    nz_log("neutralizer constructor start (inject mode, spec: %d functions)", kNeutralizedFunctionCount);
    nz_policy_summary();

    run_layer2();

    // The framework image may load after us, and the jailbreak may not be
    // active yet at constructor time. Retry at 5s and 15s.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ run_layer2(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ run_layer2(); });

    nz_log("log file: Documents/neutralizer.log");
}
