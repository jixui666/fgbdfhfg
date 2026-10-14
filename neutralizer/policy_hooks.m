// policy_hooks.m — hand-written stubs for the container-lookup entry points.
//
// These three functions are how the app locates wallet app containers from
// the built-in bundle-id list. The generated stubs (neutralizer_stubs.c)
// skip them; these versions log the policy decision and return nil/NULL, so
// the app never receives a container path.
//
// Signatures are variadic on purpose: we never read the arguments (the policy
// is block-all), so there is no risk of a signature mismatch. The caller's
// arguments simply go unused; return value is x0 = nil/NULL on arm64 AAPCS.
#import <Foundation/Foundation.h>
#include "Neutralizer.h"
#include "neutralizer_log.h"
#include "neutralizer_policy.h"

id MCMFilzaDataContainerPath(id bundleIdentifier, ...)
{
    nz_log_stub_hit("MCMFilzaDataContainerPath");
    nz_policy_hit("MCMFilzaDataContainerPath", NULL);
    return nil;
}

id MCMFilzaVirtualRoot(id a0, ...)
{
    nz_log_stub_hit("MCMFilzaVirtualRoot");
    nz_policy_hit("MCMFilzaVirtualRoot", NULL);
    return nil;
}

id KeychainLookupAppDataContainer(id bundleIdentifier, ...)
{
    nz_log_stub_hit("KeychainLookupAppDataContainer");
    nz_policy_hit("KeychainLookupAppDataContainer", NULL);
    return nil;
}
