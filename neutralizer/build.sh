#!/bin/bash
# build.sh — build the single-dylib neutralizer (macOS + Xcode).
#
# Produces build/neutralizer.dylib. Inject it WITHOUT touching the app's
# framework files:
#   * DYLD_INSERT_LIBRARIES=/path/to/neutralizer.dylib  (jailbroken), or
#   * insert_dylib into OPEN (adds LC_LOAD_DYLIB) + re-sign.
#
# Layers:
#   1. exported stubs interpose the whole collection surface (dyld binding)
#   2. constructor patches the same functions inside the loaded
#      libuiopsersvc image (RTLD_FIRST, bypasses interposition)
#
# Usage:  ./build.sh
set -euo pipefail

cd "$(dirname "$0")"

OUT="build"
INSTALL_NAME="@executable_path/neutralizer.dylib"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$OUT"

xcrun clang -arch arm64 -miphoneos-version-min=15.0 -isysroot "$SDK" \
    -fobjc-arc -fmodules -O2 \
    -dynamiclib \
    -install_name "$INSTALL_NAME" \
    -compatibility_version 1.0 -current_version 1.0 \
    -Xlinker -exported_symbols_list -Xlinker "$(pwd)/exports.txt" \
    -framework Foundation -framework Security \
    -o "$OUT/neutralizer.dylib" \
    neutralizer_shim.m neutralizer_log.m neutralizer_policy.m \
    policy_hooks.m neutralizer_stubs.c

echo "build OK: $OUT/neutralizer.dylib"
