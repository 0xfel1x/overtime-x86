# Overtime shared settings. Sourced (zsh) by every script and wrapper.
# Nothing here contains or redistributes Apple software: all inputs come from
# the Xcode installations already present on the user's own Mac.

OT_ROOT=${OT_ROOT:-${${(%):-%x}:A:h:h}}
# Generated local state (SDK copy, *.env files). Never part of the repository.
OT_HOME=${OT_HOME:-$HOME/Library/Developer/Overtime}
# Xcode that runs on this Intel Mac. Provides ld, codesign, actool, ibtool.
OT_HOST_XCODE=${OT_HOST_XCODE:-/Applications/Xcode.app}
# Newer, Apple-silicon-only Xcode. Only its SDK (headers, .tbd, .swiftinterface) is used.
OT_NEW_XCODE=${OT_NEW_XCODE:-/Applications/Xcode-27.app}
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
