#!/bin/zsh
# Builds the ToolCheck project with the Xcode Overtime prepared and runs its checks:
# Objective-C with modules, C++20, Objective-C++, C, a Swift bridging header, an asset
# catalog (actool), a xib and a storyboard (ibtool), a string catalog, a Core ML
# model and a Metal shader. Without Xcode's Metal toolchain (Xcode > Settings >
# Components) the shader is left out.
#
#   tests/tools/run.sh
#
# macOS: Debug for this Mac (run), Release for arm64 + x86_64 (run, architectures).
# iOS: Release for devices, unsigned (built only). DEVELOPER_DIR selects another Xcode.
# Shared/Adder.mlmodel and the app icon are made by fixtures.py.
set -euo pipefail
here=${0:A:h}
source "$here/../../lib/common.sh"
ot_load
xcode=${OT_PATCHED_XCODE:-${OT_XCODE_CLONE:-$OT_HOST_XCODE}}
export DEVELOPER_DIR=${DEVELOPER_DIR:-$xcode/Contents/Developer}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd "$here"
[[ -f Shared/Adder.mlmodel && -f Shared/Assets.xcassets/AppIcon.appiconset/icon.png ]] || python3 -I fixtures.py
result=0
settings=()
if ! xcrun metal --version >/dev/null 2>&1; then
    print "note: no Metal toolchain in this Xcode, the shader is left out"
    settings=('EXCLUDED_SOURCE_FILE_NAMES=*.metal')
fi

build() {  # <name> <xcodebuild arguments...>
    local name=$1
    shift
    if xcodebuild -project ToolCheck.xcodeproj -derivedDataPath "$work/dd" "$@" $settings build > "$work/$name.log" 2>&1; then
        return 0
    fi
    print "$name: build failed"
    grep -E 'error:' "$work/$name.log" | sed -e "s#^$here/##" | sort -u || tail -20 "$work/$name.log"
    result=1
    return 1
}

check() {  # <name> <app executable>
    local out sdk
    out=$("$2" --check) || { print "$1: the app failed"; result=1; return; }
    sdk=$(otool -l "$2" | awk '/LC_BUILD_VERSION/ { found = 1 } found && $1 == "sdk" { print $2; exit }')
    print "$1: $(lipo -archs "$2"), sdk $sdk"
    print -r -- "$out" | sed 's/^/  /'
}

products="$work/dd/Build/Products"
if build macos-debug -scheme ToolCheck -configuration Debug -destination "platform=macOS,arch=$(uname -m)"; then
    check macos-debug "$products/Debug/ToolCheck.app/Contents/MacOS/ToolCheck"
fi
if build macos-release -scheme ToolCheck -configuration Release -destination 'generic/platform=macOS'; then
    check macos-release "$products/Release/ToolCheck.app/Contents/MacOS/ToolCheck"
fi
if build ios-device -scheme ToolCheckiOS -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO; then
    print "ios-device: $(lipo -archs "$products/Release-iphoneos/ToolCheckiOS.app/ToolCheckiOS"), built"
fi
exit $result
