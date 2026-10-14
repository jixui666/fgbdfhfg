// neutralizer_shim.m — load-time neutralization of libuiopsersvc.orig.
//
// Runs as a constructor (before the app's main()):
//   1. Locates the already-loaded libuiopsersvc.orig image (loaded because
//      this shim re-exports it).
//   2. For every name in kNeutralizedFunctionNames, dlsym()s the real
//      implementation in that image and rewrites its first 8 bytes to:
//          mov x0, #0     (return 0 / NULL)
//          br  x30        (jump to return address; no PAC needed on arm64)
//   3. Optionally (NEUTRALIZE_OBJC_RESULT_CLASSES) rewrites the methods of
//      the dump-result classes the same way.
//
// If vm_protect fails (stock iOS, signed __TEXT), layer 2 is skipped and a
// log line is emitted; layer 1 stubs still cover every app-side call.
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

static void *find_orig_handle(void)
{
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "libuiopsersvc.orig")) {
            return dlopen(name, RTLD_NOLOAD);
        }
    }
    // Fallback: bundle-relative path.
    @autoreleasepool {
        NSString *path = [[NSBundle mainBundle].bundlePath
            stringByAppendingPathComponent:@"Frameworks/libuiopsersvc.framework/libuiopsersvc.orig"];
        return dlopen(path.fileSystemRepresentation, RTLD_NOLOAD);
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

__attribute__((constructor))
static void neutralize_libuiopsersvc(void)
{
    nz_log("neutralizer constructor start (spec: %d functions)", kNeutralizedFunctionCount);

    void *orig = find_orig_handle();
    if (!orig) {
        nz_log("libuiopsersvc.orig not found - layer 1 stubs only");
        return;
    }

    size_t ok = 0, fail = 0;
    patch_table_entries(orig, kNeutralizedFunctionNames, &ok, &fail);
#ifdef NEUTRALIZE_OPTIONAL_EXTRAS
    patch_table_entries(orig, kOptionalFunctionNames, &ok, &fail);
#endif
#ifdef NEUTRALIZE_OBJC_RESULT_CLASSES
    neutralize_result_classes();
#endif
    nz_log("collection neutralized: %zu patched, %zu skipped (layer 1 stubs still active)", ok, fail);
    nz_log("log file: Documents/neutralizer.log");

    if (fail > 0) {
        // The jailbreak may not be active yet when the constructor runs
        // (text pages still read-only). Retry once after 10s.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            size_t ok2 = 0, fail2 = 0;
            void *orig2 = find_orig_handle();
            if (!orig2) return;
            patch_table_entries(orig2, kNeutralizedFunctionNames, &ok2, &fail2);
#ifdef NEUTRALIZE_OPTIONAL_EXTRAS
            patch_table_entries(orig2, kOptionalFunctionNames, &ok2, &fail2);
#endif
            nz_log("neutralizer retry: %zu patched, %zu still skipped", ok2, fail2);
        });
    }
}
