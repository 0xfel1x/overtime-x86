#!/bin/zsh
# Step 4: make the Xcode that runs on this Mac build with the newer SDKs.
#
# The Xcode build system only resolves SDKs that sit in its own platform folders.
# This adds a symlink to each local SDK copy there; as the newest SDK of its
# platform, each becomes the default. The app is also renamed to "Xcode SDK <version>" so it is easy to
# recognise in the menu bar, the Dock and the app switcher.
# scripts/sdk-switch.sh off (the switch in the app) undoes both changes.
#
# Legal boundaries (see LEGAL.md):
#   * Works only with an Xcode the user installed themselves under Apple's license.
#   * The change stays on this Mac. Never upload, share or redistribute the result.
#   * Nothing from Xcode is contained in this repository.
set -euo pipefail
source "${0:A:h}/../lib/common.sh"
ot_require_intel
ot_load
[[ -n ${OT_SDK:-} ]] || ot_die "run scripts/make-sdk.sh first"
xcode=${OT_HOST_XCODE:A}
[[ -d $xcode/Contents/Developer ]] || ot_die "Xcode not found: $xcode"
sdks=$(ot_sdks_dir "$xcode")
plist="$xcode/Contents/Info.plist"

# An Xcode from the App Store belongs to the system; the one from Apple's .xip
# download belongs to the user who unpacked it.
[[ -w $sdks && -w $plist ]] \
    || ot_die "${xcode:t} cannot be changed by $USER (it belongs to $(stat -f %Su "$xcode")). Use an Xcode unpacked from Apple's .xip download instead."
# macOS can also block changes to other apps ("App Management" privacy setting).
probe="$sdks/.overtime-probe"
ln -sfn /dev/null "$probe" 2>/dev/null \
    || ot_die "macOS blocked changes to ${xcode:t}. Allow Overtime (or your Terminal app, for the scripts) under System Settings > Privacy & Security > App Management, then try again."
rm -f -- "$probe"

# Switch off an Xcode prepared earlier at another place, so only one is changed.
if [[ -n ${OT_PATCHED_XCODE:-} && ${OT_PATCHED_XCODE:A} != "$xcode" && -d $OT_PATCHED_XCODE ]]; then
    ot_info "switching the new SDK off in the Xcode prepared before: $OT_PATCHED_XCODE"
    ( ot_patch_off "$OT_PATCHED_XCODE" ) || ot_info "could not change $OT_PATCHED_XCODE; switch it off there by hand"
fi

# Remember the names to restore when switching off. A name set by Overtime
# (an Xcode prepared by an earlier version) stands for the plain "Xcode".
if [[ ${OT_PATCHED_XCODE:-} == "$xcode" && -n ${OT_XCODE_NAME:-} ]]; then
    name=$OT_XCODE_NAME display=${OT_XCODE_DISPLAY_NAME-}
else
    # plutil prints its errors to stdout, so a failed read must discard the output.
    name=$(plutil -extract CFBundleName raw "$plist" 2>/dev/null) || name=Xcode
    display=$(plutil -extract CFBundleDisplayName raw "$plist" 2>/dev/null) || display=
    [[ $name == "Xcode SDK "* ]] && name=Xcode
    [[ $display == "Xcode SDK "* ]] && display=Xcode
fi

ot_patch_on "$xcode"
listed=$(DEVELOPER_DIR="$xcode/Contents/Developer" xcodebuild -showsdks 2>/dev/null || true)
[[ $listed == *"-sdk $OT_SDK_CANONICAL"* ]] || ot_die "${xcode:t} does not list $OT_SDK_CANONICAL"

for p in ${=OT_PLATFORMS:-MacOSX}; do
    sdk="$OT_HOME/$p.sdk"
    canonical=$(plutil -extract CanonicalName raw "$sdk/SDKSettings.plist" 2>/dev/null) || continue
    if [[ $listed != *"-sdk $canonical"* ]]; then
        ot_info "$p: ${xcode:t} has no such platform or does not accept $canonical, left out"
        continue
    fi
    ot_info "$p: $canonical added"
    # Xcode shows its platform chooser once for every SDK build it has not presented
    # yet and opens no project until it is dismissed. Mark the linked SDK as presented
    # in the user's own Xcode preferences (where Xcode keeps such a list) so Xcode
    # opens projects straight away.
    build=$(plutil -extract ProductBuildVersion raw "$sdk/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null) || continue
    key=IDEPlatformsFirstLaunchPresentedSDKVersions-${canonical%%[0-9]*}
    if seen=$(defaults read com.apple.dt.Xcode $key 2>/dev/null) && [[ $seen != *$build* ]]; then
        defaults write com.apple.dt.Xcode $key -array-add "$build"
    fi
done

# Earlier versions made a separate copy of Xcode instead (clone.env).
unused=
if [[ -n ${OT_XCODE_CLONE:-} && ${OT_XCODE_CLONE:A} != "$xcode" && -d $OT_XCODE_CLONE ]]; then
    unused=$OT_XCODE_CLONE
    ot_info "the Xcode copy made by an earlier Overtime version is no longer needed: $unused"
fi
{
    print -r -- "OT_PATCHED_XCODE=${(qq)xcode}"
    print -r -- "OT_XCODE_NAME=${(qq)name}"
    print -r -- "OT_XCODE_DISPLAY_NAME=${(qq)display}"
    [[ -z $unused ]] || print -r -- "OT_UNUSED_COPY=${(qq)unused}"
} > "$OT_HOME/patch.env"
rm -f -- "$OT_HOME/clone.env"
ot_info "ready: ${xcode:t} builds with the SDKs $OT_SDK_VERSION (restart it if it is open)"
