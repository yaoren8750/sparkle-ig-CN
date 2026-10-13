#!/usr/bin/env bash

# Set these environment variables to match your device and bundle IDs
# export PYMOBILEDEVICE3_UDID=00000000-0000000000000000
# export LIVECONTAINER_APPID=com.kdt.livecontainer.randomizedaltstoreid
# export DEVLAUNCHER_APPID=com.socuul.scinsta-devlauncher[.randomizedaltstoreid]

set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCE_STAMP="$ROOT_DIR/packages/.sparkle-dev-resources-hash"
TWEAK_DESTINATION="Documents/Tweaks/Sparkle"

usage() {
    echo 'Usage: ./build-dev.sh [--strings|--no-strings|--bundle] [--push-only] [true]'
    echo
    echo '  (no flag)      push the dylib, and the localizations only when they changed'
    echo '  --strings      always push the localizations'
    echo '  --no-strings   never push the localizations'
    echo '  --bundle       push the complete Sparkle.bundle, FFmpeg frameworks included'
    echo '  --push-only    open LiveContainer after the push instead of the dev launcher'
    echo '  true           build a full dev IPA instead (./build.sh ipa --dev --release)'
    echo
    echo 'Base IPAs: ./build.sh ipa --bundle  (optional: --flex, --no-ext, --patch)'
    echo 'Build libFLEX only: ./build.sh ipa --buildonly --flex'
}

# Fingerprint of everything the localization bundle ships, so an unchanged
# catalog is never pushed twice. The stamp lives under packages/ because
# .theos is wiped between builds.
sparkle_resource_hash() {
    find "$ROOT_DIR/resources/Sparkle.bundle" -type f \
        \( -name '*.strings' -o -name '*.stringsdict' -o -name 'Info.plist' \) \
        -exec shasum {} + \
        | sed "s|$ROOT_DIR/||" \
        | sort \
        | shasum \
        | awk '{print $1}'
}

push_resource_bundle() {
    local mode="$1"
    local staging_directory
    staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/sparkle-dev-resources.XXXXXX")"
    if [ "$mode" = "--localizations-only" ]; then
        "$ROOT_DIR/tools/stage-sparkle-bundle.sh" "$staging_directory/Sparkle.bundle" --localizations-only
    else
        "$ROOT_DIR/tools/stage-sparkle-bundle.sh" "$staging_directory/Sparkle.bundle"
    fi
    pymobiledevice3 apps push "$LIVECONTAINER_APPID" "$staging_directory/Sparkle.bundle" "$TWEAK_DESTINATION"
    rm -rf "$staging_directory"
    mkdir -p "$(dirname "$RESOURCE_STAMP")"
    sparkle_resource_hash > "$RESOURCE_STAMP"
}

RESOURCE_MODE=auto
FULL_IPA=0
PUSH_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --strings) RESOURCE_MODE=always ;;
        --no-strings) RESOURCE_MODE=never ;;
        --bundle) RESOURCE_MODE=full ;;
        --push-only) PUSH_ONLY=1 ;;
        true) FULL_IPA=1 ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "\033[1m\033[0;31mUnknown flag: $1\033[0m"
            usage
            exit 1
            ;;
    esac
    shift
done

echo 'Note: This script is meant to be used while developing the tweak.'
echo

if [ "$FULL_IPA" -eq 1 ]; then
    ./build.sh ipa --dev --release
    exit 0
fi

# Built tweak and deploy to live container
make clean
make DEV=1 SIDELOAD=1

# Change framework locations to @rpath
install_name_tool -change "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" \
                          "@rpath/CydiaSubstrate.framework/CydiaSubstrate" \
                          ".theos/obj/debug/Sparkle.dylib" 2>/dev/null || true

# Kill running process
pymobiledevice3 developer dvt pkill "LiveContainer" --tunnel $PYMOBILEDEVICE3_UDID

pymobiledevice3 apps push "$LIVECONTAINER_APPID" .theos/obj/debug/Sparkle.dylib "$TWEAK_DESTINATION"

# The base IPA already carries a complete Sparkle.bundle, and resources resolve
# per file, so the sibling bundle only has to supply catalogs that changed.
case "$RESOURCE_MODE" in
    never)
        echo 'Skipping localizations (--no-strings)'
        ;;
    full)
        echo 'Pushing the complete Sparkle.bundle...'
        push_resource_bundle
        ;;
    always)
        echo 'Pushing localizations...'
        push_resource_bundle --localizations-only
        ;;
    auto)
        if [ -f "$RESOURCE_STAMP" ] && [ "$(cat "$RESOURCE_STAMP")" = "$(sparkle_resource_hash)" ]; then
            echo 'Localizations unchanged, skipping'
        else
            echo 'Localizations changed, pushing...'
            push_resource_bundle --localizations-only
        fi
        ;;
esac

# Launch Sparkle on iPhone, or just LiveContainer when the dev launcher is skipped
sleep 1
if [ "$PUSH_ONLY" -eq 1 ]; then
    pymobiledevice3 developer dvt launch --kill-existing --tunnel $PYMOBILEDEVICE3_UDID $LIVECONTAINER_APPID
else
    pymobiledevice3 developer dvt launch --kill-existing --tunnel $PYMOBILEDEVICE3_UDID $DEVLAUNCHER_APPID
fi
