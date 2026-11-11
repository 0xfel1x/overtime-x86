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

version=${1:-${OT_SWIFT_VERSION:-}}
[[ -n $version ]] || ot_die "run scripts/make-sdk.sh first or pass a Swift version"
name="swift-$version-RELEASE"
dest="$OT_TOOLCHAINS_DIR/$name.xctoolchain"

if [[ ! -x $dest/usr/bin/swiftc ]]; then
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
    mkdir -p "$OT_TOOLCHAINS_DIR"
    mv -- "$payload" "$dest"
fi

archs=$(lipo -archs "$dest/usr/bin/swift-frontend")
[[ $archs == *x86_64* ]] || ot_die "toolchain has no x86_64 slice ($archs)"
id=$(plutil -extract CFBundleIdentifier raw "$dest/Info.plist")
cat > "$OT_HOME/toolchain.env" <<EOF
OT_TOOLCHAIN=$dest
OT_TOOLCHAIN_ID=$id
EOF
ot_info "toolchain $name ($id, $archs) ready"
