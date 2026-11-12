# Overtime shared settings. Sourced (zsh) by every script and wrapper.
# Nothing here contains or redistributes Apple software: all inputs come from
# the Xcode installations already present on the user's own Mac.

OT_ROOT=${OT_ROOT:-${${(%):-%x}:A:h:h}}
# Generated local state (SDK copy, *.env files). Never part of the repository.
OT_HOME=${OT_HOME:-$HOME/Library/Developer/Overtime}
# Xcode paths chosen during the last setup; used as defaults so the wrappers keep
# working when the Xcodes are not in the standard places. The environment wins.
[[ -f $OT_HOME/xcode.env ]] && source "$OT_HOME/xcode.env"
# Xcode that runs on this Intel Mac. Provides ld, codesign, actool, ibtool.
OT_HOST_XCODE=${OT_HOST_XCODE:-${OT_SAVED_HOST_XCODE:-/Applications/Xcode.app}}
# Newer, Apple-silicon-only Xcode. Only its SDK (headers, .tbd, .swiftinterface) is used.
OT_NEW_XCODE=${OT_NEW_XCODE:-${OT_SAVED_NEW_XCODE:-/Applications/Xcode-27.app}}
OT_TOOLCHAINS_DIR=${OT_TOOLCHAINS_DIR:-$HOME/Library/Developer/Toolchains}
# Developer ID team of the official swift.org installer packages.
OT_SWIFT_TEAM_ID=V9AUD2URP3

ot_die() { print -u2 "overtime: $*"; exit 1; }
ot_info() { print "overtime: $*"; }

# Load results of earlier steps (sdk.env, toolchain.env) if present.
ot_load() {
    local f
    for f in "$OT_HOME"/*.env(N); do source "$f"; done
}

# Fail early on the wrong machine type.
ot_require_intel() {
    [[ $(uname -m) == x86_64 ]] || ot_die "this tool targets Intel Macs (x86_64); this machine is $(uname -m)"
}

# --- Preparing an Xcode for the newer SDKs (scripts/patch-xcode.sh, sdk-switch.sh)
# Two changes inside the Xcode bundle, both undone by "off": a symlink to each SDK
# copy in the matching platform folder (OT_PLATFORMS from sdk.env), and the name it
# shows (menu bar, Dock, app switcher), "Xcode SDK <version>" while they are in place.

ot_sdks_dir() { print -r -- "$1/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs" }

# Sets both name entries of an Xcode's Info.plist (an empty display name removes
# that entry) and lets Launch Services pick up the change.
ot_set_xcode_name() {  # <Xcode.app> <name> <display name>
    local plist="$1/Contents/Info.plist"
    plutil -replace CFBundleName -string "$2" "$plist"
    if [[ -n $3 ]]; then
        plutil -replace CFBundleDisplayName -string "$3" "$plist"
    else
        plutil -remove CFBundleDisplayName "$plist" 2>/dev/null || true
    fi
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$1" >/dev/null 2>&1 || true
}

# Removes links from an earlier run: they are the only absolute links in the SDK
# folders of the platforms.
ot_remove_sdk_links() {  # <Xcode.app>
    local old
    for old in "$1"/Contents/Developer/Platforms/*.platform/Developer/SDKs/*.sdk(N@); do
        if [[ $(readlink "$old") == /* ]]; then rm -f -- "$old"; fi
    done
}

# Xcode uses an iOS or tvOS SDK only together with a simulator
# runtime of the same version, even for device builds (asset catalogs are compiled
# with it). There are no runtimes of the newer versions for Intel Macs, so each newer
# device SDK is paired with the newest runtime of its platform installed here
# ("simctl runtime match"; kept per user in ~/Library/Developer/CoreSimulator/
# RuntimeMap.plist, only for that SDK build). "off" removes the pairings again.
ot_runtime_match() {  # on|off <Xcode.app>
    local mode=$1 json i=0 build plat version avail p sdk canonical sdk_build sdk_version family
    local -A best_build best_version
    autoload -Uz is-at-least
    export DEVELOPER_DIR="$2/Contents/Developer"
    json=$(xcrun simctl list runtimes -j 2>/dev/null) || json=
    while [[ -n $json ]] && build=$(print -r -- "$json" | plutil -extract runtimes.$i.buildversion raw -o - - 2>/dev/null); do
        plat=$(print -r -- "$json" | plutil -extract runtimes.$i.platform raw -o - - 2>/dev/null) || plat=
        version=$(print -r -- "$json" | plutil -extract runtimes.$i.version raw -o - - 2>/dev/null) || version=
        avail=$(print -r -- "$json" | plutil -extract runtimes.$i.isAvailable raw -o - - 2>/dev/null) || avail=
        if [[ $avail == true && -n $plat && -n $version ]]; then
            if [[ -z ${best_version[$plat]:-} ]] || is-at-least "${best_version[$plat]}" "$version"; then
                best_version[$plat]=$version best_build[$plat]=$build
            fi
        fi
        (( ++i ))
    done
    for p in ${=OT_PLATFORMS:-}; do
        case $p in
            iPhoneOS) family=iOS ;;
            AppleTVOS) family=tvOS ;;
            *) continue ;;
        esac
        sdk="$OT_HOME/$p.sdk"
        canonical=$(plutil -extract CanonicalName raw "$sdk/SDKSettings.plist" 2>/dev/null) || continue
        sdk_version=$(plutil -extract Version raw "$sdk/SDKSettings.plist" 2>/dev/null) || continue
        sdk_build=$(plutil -extract ProductBuildVersion raw "$sdk/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null) || continue
        if [[ $mode == off ]]; then
            xcrun simctl runtime match set "$canonical" --default --sdkBuild "$sdk_build" >/dev/null 2>&1 || true
        elif [[ -z ${best_build[$family]:-} ]]; then
            ot_info "$p: no $family simulator runtime installed; building for it needs one (Xcode > Settings > Components)"
        elif ! is-at-least "$sdk_version" "${best_version[$family]}"; then
            if xcrun simctl runtime match set "$canonical" "${best_build[$family]}" --sdkBuild "$sdk_build" >/dev/null 2>&1; then
                ot_info "$p: $canonical paired with the $family ${best_version[$family]} simulator runtime"
            else
                ot_info "$p: could not pair $canonical with a simulator runtime"
            fi
        fi
    done
}

ot_patch_on() {  # <Xcode.app>
    local p sdk dir version
    ot_remove_sdk_links "$1"
    for p in ${=OT_PLATFORMS:-MacOSX}; do
        sdk="$OT_HOME/$p.sdk"
        dir="$1/Contents/Developer/Platforms/$p.platform/Developer/SDKs"
        # A platform this Xcode does not have stays out.
        [[ -d $sdk && -d $dir ]] || continue
        version=$(plutil -extract Version raw "$sdk/SDKSettings.plist" 2>/dev/null) || continue
        ln -sfn -- "$sdk" "$dir/$p$version.sdk"
    done
    ( ot_runtime_match on "$1" )
    ot_set_xcode_name "$1" "Xcode SDK $OT_SDK_VERSION" "Xcode SDK $OT_SDK_VERSION"
}

# Uses the original names recorded in patch.env (OT_XCODE_NAME, OT_XCODE_DISPLAY_NAME).
ot_patch_off() {  # <Xcode.app>
    ( ot_runtime_match off "$1" )
    ot_remove_sdk_links "$1"
    ot_set_xcode_name "$1" "${OT_XCODE_NAME:-Xcode}" "${OT_XCODE_DISPLAY_NAME-Xcode}"
}
