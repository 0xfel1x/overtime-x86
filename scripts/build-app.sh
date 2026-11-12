#!/bin/zsh
# Builds build/Overtime.app, the drag-and-drop front end for the setup scripts.
#
# It is compiled from App/ with the Xcode that runs on this Mac and carries a copy
# of lib/, scripts/ and bin/ from this repository. Like the repository, the app
# contains no Apple software. It is signed ad hoc, for use on the Mac it was built on.
set -euo pipefail
source "${0:A:h}/../lib/common.sh"
[[ -d $OT_HOST_XCODE/Contents/Developer ]] && export DEVELOPER_DIR="$OT_HOST_XCODE/Contents/Developer"

app="$OT_ROOT/build/Overtime.app"
rm -rf -- "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/overtime"

# Build with the SDK that belongs to this Xcode's own compiler. In an Xcode that
# Overtime prepared, the default SDK is the newer one, which that compiler cannot read.
sdk="${DEVELOPER_DIR:-$(xcode-select -p)}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
xcrun swiftc -O -swift-version 5 -parse-as-library -target x86_64-apple-macos13.0 -sdk "$sdk" \
    "$OT_ROOT"/App/*.swift -o "$app/Contents/MacOS/Overtime"
cp "$OT_ROOT/App/Info.plist" "$app/Contents/Info.plist"
cp "$OT_ROOT/App/Overtime.icns" "$app/Contents/Resources/Overtime.icns"
cp -R "$OT_ROOT/lib" "$OT_ROOT/scripts" "$OT_ROOT/bin" "$app/Contents/Resources/overtime/"
rm -f -- "$app/Contents/Resources/overtime/scripts/build-app.sh"
find "$app" -name .DS_Store -delete
codesign --force --sign - "$app"
ot_info "built $app"

# --zip additionally packs the app for a release download. The archive goes to
# releases/, away from build/, so unpacking it never collides with the built app.
if [[ ${1:-} == --zip ]]; then
    version=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
    mkdir -p "$OT_ROOT/releases"
    zip="$OT_ROOT/releases/Overtime-$version.zip"
    rm -f -- "$zip"
    ditto -c -k --keepParent "$app" "$zip"
    ot_info "packed $zip"
fi
