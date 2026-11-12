#!/bin/zsh
# Step 1: make local, Intel-usable copies of the SDKs in the newer Xcode.
#
# The macOS SDK is required. The others (iOS, tvOS, their simulators and DriverKit)
# are copied when the newer Xcode has them and a test link with the older linker
# works. watchOS and visionOS are left out. Each copy gets two changes:
#
#   * The older Intel-capable linker rejects the new architecture token
#     "arm64e.x1" in the .tbd link stubs. The copy renames it to "i386", which no
#     build with these SDKs links. Every symbol listed for arm64e.x1 is also listed
#     for arm64e, and the older linker links arm64 code against the arm64e entries.
#   * SwiftUI's State macro declarations are removed (see below).
#
# The copies are APFS clones on the user's own disk. They must never be committed
# or redistributed (see LEGAL.md); .gitignore excludes them.
#
# OT_SDK_PLATFORMS limits the platforms, for example "MacOSX iPhoneOS iPhoneSimulator".
set -euo pipefail
source "${0:A:h}/../lib/common.sh"
ot_require_intel

[[ -d $OT_HOST_XCODE/Contents/Developer ]] || ot_die "host Xcode not found: $OT_HOST_XCODE (set OT_HOST_XCODE)"
export DEVELOPER_DIR="$OT_HOST_XCODE/Contents/Developer"
xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 \
    || ot_die "open ${OT_HOST_XCODE:t} once and let it finish its first-launch setup, then try again"
# The older Xcode's own clang and linker, whatever toolchain is selected.
clang="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
new_platforms="$OT_NEW_XCODE/Contents/Developer/Platforms"

# Target for the test link of each platform; empty means no test link.
typeset -A link_targets=(
    MacOSX           x86_64-apple-macos13
    iPhoneOS         arm64-apple-ios17
    iPhoneSimulator  x86_64-apple-ios17-simulator
    AppleTVOS        arm64-apple-tvos17
    AppleTVSimulator x86_64-apple-tvos17-simulator
    DriverKit        ''
)
platforms=(${=OT_SDK_PLATFORMS:-MacOSX iPhoneOS iPhoneSimulator AppleTVOS AppleTVSimulator DriverKit})
(( ${platforms[(Ie)MacOSX]} )) || platforms=(MacOSX $platforms)

# The macOS SDK decides the Swift compiler version for all of them.
src_link="$new_platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
[[ -d $src_link ]] || ot_die "no macOS SDK in $OT_NEW_XCODE (set OT_NEW_XCODE)"
iface="${src_link:A}/usr/lib/swift/Swift.swiftmodule/x86_64-apple-macos.swiftinterface"
[[ -f $iface ]] || ot_die "SDK has no x86_64 Swift interfaces; Intel builds are not possible with it"
swift_version=$(sed -n 's/^\/\/ swift-compiler-version: Apple Swift version \([0-9.]*\).*/\1/p' "$iface" | head -1)
[[ -n $swift_version ]] || ot_die "could not read the Swift compiler version from $iface"

mkdir -p "$OT_HOME"
probe=$(mktemp -d)
trap 'rm -rf -- "$probe"' EXIT
print 'int main(void){return 0;}' > "$probe/p.c"

# Copies, adjusts and tests the SDK of one platform and adds it to "copied".
# Called outside of conditions so that errexit stays in force inside.
copied=()
copy_sdk() {
    local p=$1 src_link="$new_platforms/$1.platform/Developer/SDKs/$1.sdk"
    if [[ ! -d $src_link ]]; then
        ot_info "$p: not in ${OT_NEW_XCODE:t}, skipped"
        return 0
    fi
    local src=${src_link:A} version files macro old
    version=$(plutil -extract Version raw "$src/SDKSettings.plist")
    local dest="$OT_HOME/$p$version-x86.sdk"
    local work="$dest.partial"
    rm -rf -- "$work"
    cp -Rc -- "$src" "$work"

    files=("${(@f)$(grep -rl --include='*.tbd' 'arm64e\.x1' "$work" || true)}")
    files=(${files:#})
    if (( ${#files} )); then
        print -rN -- "${files[@]}" | xargs -0 perl -pi -e 's/arm64e\.x1-/i386-/g'
    fi
    local tbd_count=${#files}

    # SDK 27 also declares SwiftUI's State as a macro. The older Xcode implements
    # that macro in an earlier form whose expansion calls a function the newer SDK
    # no longer has, so every "@State private var" fails to compile. Without the
    # declarations, @State is the property wrapper it has always been.
    macro='type: "StateMacro"'
    files=("${(@f)$(grep -rl --include='*.swiftinterface' "$macro" "$work" || true)}")
    files=(${files:#})
    if (( ${#files} )); then
        print -rN -- "${files[@]}" | xargs -0 perl -0pi -e \
            's/^[^\n]*\bmacro State\b[^\n]*#externalMacro\(\s*module:\s*"SwiftUIMacros",\s*type:\s*"StateMacro"\s*\)\n//mg'
        if grep -rq --include='*.swiftinterface' "$macro" "$work"; then
            ot_info "$p: warning: some State macro declarations are left; \"@State private var\" may not compile"
        fi
    fi
    local state_count=${#files}

    # SDK 27 renamed @AssistantIntent/@AssistantEntity/@AssistantEnum(schema:) to
    # @AppIntent/@AppEntity/@AppEnum(schema:), and the member they generate from
    # __assistantSchema... to __appSchema... The older Xcode's implementation still
    # generates the old member, which the newer SDK accepts (the deprecated spellings
    # still compile). Declaring the old member name for the new spellings as well lets
    # them work too.
    files=("${(@f)$(grep -rl --include='*.swiftinterface' 'names: named(__appSchema' "$work" || true)}")
    files=(${files:#})
    if (( ${#files} )); then
        print -rN -- "${files[@]}" | xargs -0 perl -pi -e \
            's/named\(__appSchema(Intent|Entity|Enum)\)(\) public macro App\1<)/named(__appSchema$1), named(__assistantSchema$1)$2/g'
    fi

    local target=${link_targets[$p]:-} result="no test link"
    if [[ -n $target ]]; then
        if ! "$clang" -isysroot "$work" -target "$target" "$probe/p.c" -o "$probe/$p" 2>"$probe/$p.log"; then
            ot_info "$p: the older linker cannot use this SDK, skipped: $(head -1 "$probe/$p.log")"
            rm -rf -- "$work"
            [[ $p == MacOSX ]] && ot_die "the macOS SDK is required"
            return 0
        fi
        [[ $p == MacOSX ]] && "$probe/$p"
        result="test link ok"
    fi

    rm -rf -- "$dest"
    mv -- "$work" "$dest"
    ln -sfn -- "${dest:t}" "$OT_HOME/$p.sdk"
    # Remove copies of earlier SDK versions of this platform.
    for old in "$OT_HOME"/${p}[0-9]*-x86.sdk(N/); do
        [[ $old == "$dest" ]] || rm -rf -- "${old:?}"
    done
    copied+=($p)
    ot_info "$p $version: $tbd_count .tbd files adjusted, State macro removed from $state_count interfaces, $result"
}

for p in $platforms; do
    (( ${+link_targets[$p]} )) || ot_die "unknown platform: $p"
    copy_sdk "$p"
done

sdk=$OT_HOME/MacOSX.sdk
cat > "$OT_HOME/sdk.env" <<EOF
OT_SDK=$sdk
OT_SDK_VERSION=$(plutil -extract Version raw "$sdk/SDKSettings.plist")
OT_SDK_CANONICAL=$(plutil -extract CanonicalName raw "$sdk/SDKSettings.plist")
OT_SWIFT_VERSION=$swift_version
OT_PLATFORMS='$copied'
EOF
print -r -- "OT_SAVED_HOST_XCODE=${(qq)OT_HOST_XCODE}" > "$OT_HOME/xcode.env"
print -r -- "OT_SAVED_NEW_XCODE=${(qq)OT_NEW_XCODE}" >> "$OT_HOME/xcode.env"
ot_info "ready: ${#copied} SDKs in $OT_HOME (${copied}), need Swift $swift_version"
