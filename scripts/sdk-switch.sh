#!/bin/zsh
# Switches the Overtime changes in the prepared Xcode on or off.
#
#   sdk-switch.sh on | off | status
#
# "off" removes the link to the SDK copy from that Xcode and gives it back its
# original name. It then behaves exactly as without Overtime, including plain
# swiftc, swift build and xcodebuild in the Terminal, which otherwise pick the
# newer SDK with a compiler that cannot read it. "on" makes both changes again.
# Restart Xcode after switching.
set -euo pipefail
source "${0:A:h}/../lib/common.sh"
ot_load
# clone.env: the separate copy made by versions before 3.0.
xcode=${OT_PATCHED_XCODE:-${OT_XCODE_CLONE:-}}
[[ -n ${OT_SDK:-} && -n $xcode ]] || ot_die "nothing prepared yet: run the setup first"
[[ -d $xcode ]] || ot_die "the prepared Xcode is missing: $xcode (run the setup again)"

case ${1:-status} in
    on) ot_patch_on "$xcode" ;;
    off) ot_patch_off "$xcode" ;;
    status) ;;
    *) ot_die "usage: ${0:t} on|off|status" ;;
esac
[[ -L $(ot_sdks_dir "$xcode")/MacOSX$OT_SDK_VERSION.sdk ]] && print on || print off
