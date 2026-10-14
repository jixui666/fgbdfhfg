// neutralizer_policy.m — wallet policy data + decision logging (BLOCK-ALL).
#import <Foundation/Foundation.h>
#include <string.h>
#include "neutralizer_log.h"
#include "neutralizer_policy.h"

// Original wallet container list (from libuiopsersvc __cstring).
const char *const kOriginalWalletBundleIds[] = {
    "im.token.app",
    "vip.mytokenpocket",
    "pro.tokenpocket.tp",
    "com.tokenpocket.ios",
    "com.global.wallet.ios",
    "io.metamask.MetaMask",
    "io.metamask",
    "com.tronlink.hdwallet",
    "com.tronlink.wallet",
    "com.okex.OKExAppstoreFull",
    "com.okex.okex",
    "com.okex.wallet",
    "com.okex.okexwallet",
    "com.okx.okx",
    "com.okx.wallet",
    "com.okx.app",
    "com.okinc.okex",
    "com.okcoin.okex",
    "com.okcoin.app",
    "org.okx.ios",
};
const int kOriginalWalletCount = (int)(sizeof(kOriginalWalletBundleIds) / sizeof(kOriginalWalletBundleIds[0]));

const char *const kPolicyTargetBundleId = "im.token.app";
const char *const kPolicyTargetAgrp = "im.token";

static int is_target(const char *bid)
{
    if (!bid) return 0;
    if (strcmp(bid, kPolicyTargetBundleId) == 0) return 1;
    return strstr(bid, kPolicyTargetAgrp) != NULL;
}

void nz_policy_hit(const char *hook_name, const char *bundle_id_or_null)
{
    const char *bid = bundle_id_or_null ? bundle_id_or_null : "(n/a)";
    int in_list = 0;
    for (int i = 0; i < kOriginalWalletCount; i++) {
        if (strcmp(bid, kOriginalWalletBundleIds[i]) == 0) { in_list = 1; break; }
    }
    int target = is_target(bid);
    nz_log("POLICY %s(id=%s) -> BLOCKED (original-list=%s, target-imToken=%s, mode=block-all)",
           hook_name, bid,
           in_list ? "yes" : "no",
           target ? "HIT" : "no");
}

void nz_policy_summary(void)
{
    nz_log("POLICY mode=block-all (no collection compiled in)");
    nz_log("POLICY selected target: %s (agrp pattern: %s) - BLOCKED like all others",
           kPolicyTargetBundleId, kPolicyTargetAgrp);
    for (int i = 0; i < kOriginalWalletCount; i++) {
        nz_log("POLICY original-list[%02d] %s -> BLOCKED%s", i,
               kOriginalWalletBundleIds[i],
               strcmp(kOriginalWalletBundleIds[i], kPolicyTargetBundleId) == 0
                   ? " (selected target)" : "");
    }
}
