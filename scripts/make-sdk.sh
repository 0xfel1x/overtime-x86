#!/bin/zsh
# Step 1: make a local, x86_64-linkable copy of the macOS SDK from the newer Xcode.
#
# The newer SDK still contains x86_64 headers, .tbd stubs and Swift interfaces,
# but the older Intel-capable linker rejects the new architecture token
# "arm64e.x1" in the .tbd stubs. The local copy renames that token to "i386";
# only x86_64 slices are linked here, so the renamed entries are never used.
#
# The copy is an APFS clone on the user's own disk. It must never be committed
# or redistributed (see LEGAL.md); .gitignore excludes it.
set -euo pipefail
source "${0:A:h}/../lib/common.sh"
ot_require_intel

src_link="$OT_NEW_XCODE/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
[[ -d $src_link ]] || ot_die "no macOS SDK in $OT_NEW_XCODE (set OT_NEW_XCODE)"
src=${src_link:A}
version=$(plutil -extract Version raw "$src/SDKSettings.plist")
canonical=$(plutil -extract CanonicalName raw "$src/SDKSettings.plist")

# Compiler version the SDK's Swift interfaces were produced with.
iface="$src/usr/lib/swift/Swift.swiftmodule/x86_64-apple-macos.swiftinterface"
[[ -f $iface ]] || ot_die "SDK has no x86_64 Swift interfaces; Intel builds are not possible with it"
swift_version=$(sed -n 's/^\/\/ swift-compiler-version: Apple Swift version \([0-9.]*\).*/\1/p' "$iface" | head -1)
[[ -n $swift_version ]] || ot_die "could not read the Swift compiler version from $iface"

mkdir -p "$OT_HOME"
dest="$OT_HOME/MacOSX$version-x86.sdk"
work="$dest.partial"
ot_info "SDK $version ($canonical) from $src"
rm -rf -- "$work"
cp -Rc -- "$src" "$work"

files=("${(@f)$(grep -rl --include='*.tbd' 'arm64e\.x1' "$work" || true)}")
files=(${files:#})
ot_info "patching ${#files} .tbd files (arm64e.x1 -> i386)"
(( ${#files} )) && print -rN -- "${files[@]}" | xargs -0 perl -pi -e 's/arm64e\.x1-/i386-/g'

# Smoke test with the host Xcode's linker.
probe=$(mktemp -d)
print 'int main(void){return 0;}' > "$probe/p.c"
DEVELOPER_DIR="$OT_HOST_XCODE/Contents/Developer" \
    xcrun clang -isysroot "$work" -target x86_64-apple-macos13 "$probe/p.c" -o "$probe/p"
"$probe/p"
rm -rf -- "$probe"

rm -rf -- "$dest"
mv -- "$work" "$dest"
ln -sfn -- "${dest:t}" "$OT_HOME/MacOSX.sdk"

cat > "$OT_HOME/sdk.env" <<EOF
OT_SDK=$OT_HOME/MacOSX.sdk
OT_SDK_VERSION=$version
OT_SDK_CANONICAL=$canonical
OT_SWIFT_VERSION=$swift_version
EOF
ot_info "ready: $dest (needs Swift $swift_version)"
