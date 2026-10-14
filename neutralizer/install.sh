#!/bin/bash
# install.sh — install the neutralization shim into OPEN.app and re-sign.
#
# Steps:
#   1. rename the shipped libuiopsersvc binary to libuiopsersvc.orig
#      (kept: the framework's own .bak file is left untouched)
#   2. fix the .orig install name
#   3. copy the shim over the framework binary
#   4. re-sign the whole app (required — CodeResources hashes changed)
set -euo pipefail

cd "$(dirname "$0")"

APP="${OPEN_APP_PATH:-..}"                                  # …/OPEN.app
FW="$APP/Frameworks/libuiopsersvc.framework"
ORIG_ID="@rpath/libuiopsersvc.framework/libuiopsersvc.orig"

[ -f build/libuiopsersvc.dylib ] || { echo "run ./build.sh first" >&2; exit 1; }

# 1+2) keep the shipped binary as the re-export target
if [ ! -f "$FW/libuiopsersvc.orig" ]; then
    cp "$FW/libuiopsersvc" "$FW/libuiopsersvc.orig"
fi
xcrun install_name_tool -id "$ORIG_ID" "$FW/libuiopsersvc.orig"

# 3) install shim
cp build/libuiopsersvc.dylib "$FW/libuiopsersvc"

# 4) re-sign — pick the tool that matches how the app was signed.
if command -v ldid >/dev/null 2>&1; then
    # jailbroken toolchain: keep existing entitlements
    ldid -e "$APP/OPEN" > /tmp/OPEN.ent.plist 2>/dev/null || true
    ldid -S/tmp/OPEN.ent.plist "$FW/libuiopsersvc.orig" || ldid -S "$FW/libuiopsersvc.orig"
    ldid -S/tmp/OPEN.ent.plist "$FW/libuiopsersvc" || ldid -S "$FW/libuiopsersvc"
    ldid -S/tmp/OPEN.ent.plist "$APP/OPEN" || ldid -S "$APP/OPEN"
else
    echo "ldid not found. Re-sign manually, e.g.:"
    echo "  codesign -f -s \"Apple Development: you@example.com (XXXXXXXXXX)\" \\"
    echo "      --entitlements <app entitlements> \"$APP\""
    exit 1
fi

echo "installed. verify with: otool -l $FW/libuiopsersvc | grep -A2 REEXPORT"
