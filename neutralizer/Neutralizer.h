// Neutralizer.h — spec header for the libuiopsersvc neutralization shim.
//
// Single-dylib inject mode (no framework file replacement, no .orig):
//   * injected via DYLD_INSERT_LIBRARIES or an added LC_LOAD_DYLIB;
//   * Layer 1 (always active, no privileges needed): the dylib exports stubs
//     for every collection entry point (generated list in
//     neutralizer_stubs.c + hand-written policy hooks in policy_hooks.m).
//     dyld interposition makes all app-side calls land on the stubs, which
//     return 0/NULL — the original collectors are never reached.
//   * Layer 2 (active when text pages can be made writable, i.e. jailbroken):
//     a load-time constructor resolves the same symbols inside the loaded
//     libuiopsersvc image (RTLD_FIRST, bypassing interposition) and rewrites
//     their prologue to `mov x0,#0 ; br x30`, so even intra-framework calls
//     into the collection code are dead.
//
// Policy: BLOCK-ALL — no collection capability is compiled in. Every
// intercepted call is logged to Documents/neutralizer.log, including the
// per-wallet policy decisions (original bundle-id list vs. selected target).
//
// The "spec" is tools/gen_stubs.py: edit NEUTRALIZED_PREFIXES /
// NEUTRALIZED_EXACT / OPTIONAL_PREFIXES there, re-run it, and both the stub
// exports and the patch table are regenerated.
#ifndef NEUTRALIZER_H
#define NEUTRALIZER_H

#include <stddef.h>

// Layer-2 patch table (generated; names are C-level, no leading underscore).
extern const int kNeutralizedFunctionCount;
extern const char *kNeutralizedFunctionNames[];
// Optional extras table (see gen_stubs.py OPTIONAL_PREFIXES); empty unless
// NEUTRALIZE_OPTIONAL_EXTRAS is defined.
extern const char *kOptionalFunctionNames[];

// --- build-time knobs -----------------------------------------------------
// Uncomment to also neutralize vn_copyfile_vfs / vn_fileredirect /
// vn_fileunredirect (shared with jailbreak file-management UI features).
// #define NEUTRALIZE_OPTIONAL_EXTRAS 1

// Uncomment to also rewrite the ObjC method implementations of the dump
// result class(es) inside libuiopsersvc. Normally unnecessary: the result
// objects are only produced by collection code that is already dead.
// #define NEUTRALIZE_OBJC_RESULT_CLASSES 1

#endif // NEUTRALIZER_H
