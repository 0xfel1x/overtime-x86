#!/bin/zsh
# Optional step 4: a private, local Xcode IDE setup that can build against the
# newer SDK.
#
# The Xcode build system only resolves SDKs that sit in its own platform folder.
# Instead of modifying the user's installed Xcode, this makes an APFS clone of it
# on the same disk (almost no extra space) and adds one symlink to the local SDK
# copy inside the clone.
#
# Legal boundaries (see LEGAL.md):
#   * Works only with an Xcode the user installed themselves under Apple's license.
#   * The clone stays on this Mac. Never upload, share or redistribute it.
#   * Nothing from Xcode is contained in this repository.
set -euo pipefail
source "${0:A:h}/../lib/common.sh"
ot_require_intel
ot_load
[[ -n ${OT_SDK:-} ]] || ot_die "run scripts/make-sdk.sh first"
[[ -d $OT_HOST_XCODE ]] || ot_die "host Xcode not found: $OT_HOST_XCODE"

# The copy goes next to the other apps in /Applications. Where that folder is not
# writable for this user, or is on another volume, it goes to ~/Applications.
apps=/Applications
if [[ ! -w $apps || $(stat -f %d "$apps") != $(stat -f %d "$OT_HOST_XCODE") ]]; then
    apps=$HOME/Applications
fi
clone=${OT_CLONE:-$apps/Xcode-SDK$OT_SDK_VERSION.app}
if [[ -e $clone ]]; then
    ot_info "clone exists: $clone"
else
    mkdir -p "${clone:h}"
    [[ $(stat -f %d "$OT_HOST_XCODE") == $(stat -f %d "${clone:h}") ]] \
        || ot_die "clone target must be on the same APFS volume as $OT_HOST_XCODE"
    ot_info "cloning $OT_HOST_XCODE -> $clone (APFS clone, takes a few minutes)"
    rm -rf -- "$clone.partial"
    cp -Rc -- "$OT_HOST_XCODE" "$clone.partial"
    mv -- "$clone.partial" "$clone"
fi

sdks="$clone/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs"
ln -sfn -- "$OT_SDK" "$sdks/MacOSX$OT_SDK_VERSION.sdk"
DEVELOPER_DIR="$clone/Contents/Developer" xcodebuild -showsdks 2>/dev/null | grep -q "$OT_SDK_CANONICAL" \
    || ot_die "the clone does not list $OT_SDK_CANONICAL"

# Make the copy recognisable: the menu bar, the Dock and the app switcher then show
# "Xcode SDK 27.2" instead of "Xcode". Only the two name entries in the copy's
# Info.plist change. The version is left alone: Xcode's About window reads only
# the digits of it, so text added there would show up as a wrong version number.
label="Xcode SDK $OT_SDK_VERSION"
plutil -replace CFBundleName -string "$label" "$clone/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$label" "$clone/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string \
    "$(plutil -extract CFBundleShortVersionString raw "$OT_HOST_XCODE/Contents/Info.plist")" "$clone/Contents/Info.plist"

# Xcode shows its platform chooser once for every SDK build it has not presented
# yet and opens no project until it is dismissed. Mark the linked SDK as presented
# in the user's own Xcode preferences so the clone opens projects straight away.
build=$(plutil -extract ProductBuildVersion raw "$OT_SDK/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null || true)
key=IDEPlatformsFirstLaunchPresentedSDKVersions-macosx
if [[ -n $build ]] && seen=$(defaults read com.apple.dt.Xcode $key 2>/dev/null) && [[ $seen != *$build* ]]; then
    defaults write com.apple.dt.Xcode $key -array-add "$build"
fi

print -r -- "OT_XCODE_CLONE=${(qq)clone}" > "$OT_HOME/clone.env"
ot_info "ready: open projects with $clone"
