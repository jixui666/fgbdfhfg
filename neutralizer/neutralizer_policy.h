// neutralizer_policy.h — wallet policy spec + decision logging (BLOCK-ALL).
//
// The policy mirrors the original binary's built-in wallet list so the log
// can show, per intercepted call, what WOULD have been selected. The only
// policy action compiled in is BLOCK: no collection capability exists in
// this dylib.
#ifndef NEUTRALIZER_POLICY_H
#define NEUTRALIZER_POLICY_H

#ifdef __cplusplus
extern "C" {
#endif

// Original wallet container bundle ids, taken from the framework's built-in
// list (__cstring, used with FILZA_MCM_IGNORE_CUSTOM_IDENTIFIERS).
extern const char *const kOriginalWalletBundleIds[];
extern const int kOriginalWalletCount;

// Selected target shown in policy logs (imToken). Policy is BLOCK: even the
// target is never collected.
extern const char *const kPolicyTargetBundleId;   // "im.token.app"
extern const char *const kPolicyTargetAgrp;       // "im.token" (keychain agrp pattern)

// Log the policy decision for one intercepted call.
void nz_policy_hit(const char *hook_name, const char *bundle_id_or_null);

// Log the full policy (original list + target + mode) at startup.
void nz_policy_summary(void);

#ifdef __cplusplus
}
#endif

#endif // NEUTRALIZER_POLICY_H
