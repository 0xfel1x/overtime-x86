#!/bin/zsh
# Runs all steps in order. The last one changes the Xcode that runs on this Mac;
# scripts/sdk-switch.sh off (ot-sdk off) undoes that.
# build/Overtime.app (scripts/build-app.sh) does the same from a window.
set -euo pipefail
here=${0:A:h}
"$here/make-sdk.sh"
"$here/install-toolchain.sh"
"$here/make-xcconfig.sh"
"$here/patch-xcode.sh"
print "\nDone. Add $here:h/bin to PATH, then try: ot-swiftc --version"
