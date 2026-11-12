#!/bin/zsh
# Step 2: install the open-source swift.org toolchain whose version matches the
# SDK's Swift interfaces. swift.org macOS toolchains are universal (x86_64 + arm64)
# and Apache-2.0 licensed; they are downloaded from swift.org, never bundled here.
#
# Usage: install-toolchain.sh [swift-version]   (default: detected by make-sdk.sh)
set -euo pipefail
source "${0:A:h}/../lib/common.sh"
ot_require_intel
ot_load
export DEVELOPER_DIR="$OT_HOST_XCODE/Contents/Developer"

version=${1:-${OT_SWIFT_VERSION:-}}
[[ -n $version ]] || ot_die "run scripts/make-sdk.sh first or pass a Swift version"
name="swift-$version-RELEASE"
dest="$OT_TOOLCHAINS_DIR/$name.xctoolchain"

if [[ ! -x $dest/usr/bin/swiftc ]]; then
    mkdir -p "$OT_TOOLCHAINS_DIR"
    free_gb=$(( $(df -k "$OT_TOOLCHAINS_DIR" | awk 'NR==2 {print $4}') / 1048576 ))
    (( free_gb >= 8 )) || ot_die "not enough free disk space: the Swift toolchain needs about 8 GB, $free_gb GB are free"
    url="https://download.swift.org/swift-$version-release/xcode/$name/$name-osx.pkg"
    tmp=$(mktemp -d)
    trap 'rm -rf -- "$tmp"' EXIT
    ot_info "downloading $url"
    curl -fL --retry 3 -o "$tmp/$name.pkg" "$url"
    sig=$(pkgutil --check-signature "$tmp/$name.pkg")
    print -r -- "$sig" | grep -q "($OT_SWIFT_TEAM_ID)" \
        || ot_die "package is not signed by swift.org (team $OT_SWIFT_TEAM_ID):"$'\n'"$sig"
    print -r -- "$sig" | grep -q 'trusted by the Apple notary service' \
        || ot_die "package is not notarized"
    pkgutil --expand-full "$tmp/$name.pkg" "$tmp/x"
    payload=$(print -l "$tmp"/x/*.pkg/Payload(N) | head -1)
    [[ -x $payload/usr/bin/swiftc ]] || ot_die "unexpected package layout"
    mv -- "$payload" "$dest"
fi

# The swift.org toolchain ships no Apple linker, and its clang looks for "ld" next to
# itself before falling back to PATH. When Xcode resolves Swift packages it compiles
# their manifests with this toolchain and a PATH that has no linker, which fails with
# "posix_spawn failed". A small forwarder to the active Xcode's linker fixes that.
if [[ ! -e $dest/usr/bin/ld ]]; then
    cat > "$dest/usr/bin/ld" <<'FORWARD'
#!/bin/sh
# Added by Overtime: hand over to the linker of the active Xcode.
dev=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
exec "$dev/Toolchains/XcodeDefault.xctoolchain/usr/bin/ld" "$@"
FORWARD
    chmod +x "$dest/usr/bin/ld"
fi

archs=$(lipo -archs "$dest/usr/bin/swift-frontend")
[[ $archs == *x86_64* ]] || ot_die "toolchain has no x86_64 slice ($archs)"
id=$(plutil -extract CFBundleIdentifier raw "$dest/Info.plist")
cat > "$OT_HOME/toolchain.env" <<EOF
OT_TOOLCHAIN=$dest
OT_TOOLCHAIN_ID=$id
EOF

# Record in each SDK copy with Swift which toolchain belongs to it. The Xcode build
# system reads this key and then picks the matching Swift compiler for every project
# built against the SDK, without any project setting. (DriverKit has no Swift and
# keeps the older Xcode's own compiler.)
#
# Apple's Swift compiler loads cross-import overlays (PhotosPicker from PhotosUI with
# SwiftUI, @Query from SwiftData with SwiftUI, ...) by default; the swift.org one
# only when asked. SWIFT_TOOLCHAIN_FLAGS is a hidden Xcode build setting meant for
# such toolchain flags, so as a default of the SDK it reaches every project.
flags='$(inherited) -Xfrontend -enable-cross-import-overlays'
for p in ${=OT_PLATFORMS:-MacOSX}; do
    sdk="$OT_HOME/$p.sdk"
    [[ -d $sdk/usr/lib/swift ]] || continue
    for settings in "$sdk"/SDKSettings.{json,plist}(N); do
        plutil -replace Toolchains -json "[\"$id\"]" "$settings"
        plutil -replace DefaultProperties.SWIFT_TOOLCHAIN_FLAGS -string "$flags" "$settings"
    done
done
ot_info "toolchain $name ($id, $archs) ready"
