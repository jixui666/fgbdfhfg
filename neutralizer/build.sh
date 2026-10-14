#!/bin/bash
# build.sh — build the libuiopsersvc neutralization shim (macOS + Xcode).
#
# Produces build/libuiopsersvc.dylib, a drop-in replacement for
# OPEN.app/Frameworks/libuiopsersvc.framework/libuiopsersvc:
#   * exports stubs for the whole collection surface (layer 1)
#   * re-exports libuiopsersvc.orig for every other symbol (jailbreak features
#     keep working)
#   * constructor patches the collection functions inside the .orig (layer 2)
#
# Usage:  ./build.sh [path/to/libuiopsersvc.orig]
#   Default orig path: ../Frameworks/libuiopsersvc.framework/libuiopsersvc.orig
set -euo pipefail

cd "$(dirname "$0")"

APP="${OPEN_APP_PATH:-..}"                                  # …/OPEN.app
FW="$APP/Frameworks/libuiopsersvc.framework"
ORIG="${1:-$FW/libuiopsersvc.orig}"
OUT="build"
SHIM_ID="@rpath/libuiopsersvc.framework/libuiopsersvc"
ORIG_ID="@rpath/libuiopsersvc.framework/libuiopsersvc.orig"

if [ ! -f "$ORIG" ]; then
    # fallback chain: current (shipped) framework binary, then the CI repo layout
    if [ -f "$FW/libuiopsersvc" ]; then
        ORIG="$FW/libuiopsersvc"
    elif [ -f "../vendor/libuiopsersvc.framework/libuiopsersvc" ]; then
        ORIG="../vendor/libuiopsersvc.framework/libuiopsersvc"
    else
        echo "error: no libuiopsersvc(.orig) found in $FW or ../vendor" >&2
        exit 1
    fi
fi

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$OUT"

# 1) give the original its own install name so it can be re-exported
#    without colliding with the shim
cp "$ORIG" "$OUT/libuiopsersvc.orig"
xcrun install_name_tool -id "$ORIG_ID" "$OUT/libuiopsersvc.orig"

# 2) compile the shim (arm64; both target binaries are plain arm64)
xcrun clang -arch arm64 -miphoneos-version-min=15.0 -isysroot "$SDK" \
    -fobjc-arc -fmodules -O2 \
    -dynamiclib \
    -install_name "$SHIM_ID" \
    -compatibility_version 1.0 -current_version 1.0 \
    -Xlinker -reexport_library -Xlinker "$OUT/libuiopsersvc.orig" \
    -Xlinker -exported_symbols_list -Xlinker "$(pwd)/exports.txt" \
    -framework Foundation -framework Security \
    -o "$OUT/libuiopsersvc.dylib" \
    neutralizer_shim.m neutralizer_log.m neutralizer_stubs.c

echo "build OK: $OUT/libuiopsersvc.dylib"
echo "next: ./install.sh"
