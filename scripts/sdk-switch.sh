#!/bin/zsh
# Switches the newer SDK on or off in the Xcode that Overtime prepared.
#
#   sdk-switch.sh on | off | status
#
# "off" removes the link to the SDK copy from that Xcode. It then behaves exactly
# as before, including plain swiftc, swift build and xcodebuild in the Terminal,
# which otherwise pick the newer SDK with a compiler that cannot read it.
# "on" puts the link back. Nothing else is touched; restart Xcode after switching.
set -euo pipefail
source "${0:A:h}/../lib/common.sh"
ot_load
[[ -n ${OT_SDK:-} && -n ${OT_XCODE_CLONE:-} ]] || ot_die "nothing prepared yet: run the setup first"
[[ -d $OT_XCODE_CLONE ]] || ot_die "the prepared Xcode is missing: $OT_XCODE_CLONE (run the setup again)"

link="$OT_XCODE_CLONE/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX$OT_SDK_VERSION.sdk"
case ${1:-status} in
    on)  ln -sfn -- "$OT_SDK" "$link" ;;
    off) [[ -L $link ]] && rm -f -- "$link" ;;
    status) ;;
    *) ot_die "usage: ${0:t} on|off|status" ;;
esac
[[ -L $link ]] && print on || print off
