#!/bin/zsh
# Runs the required steps in order. The Xcode IDE clone is opt-in: --with-ide.
set -euo pipefail
here=${0:A:h}
"$here/make-sdk.sh"
"$here/install-toolchain.sh"
"$here/make-xcconfig.sh"
[[ ${1:-} == --with-ide ]] && "$here/make-xcode-clone.sh"
print "\nDone. Add $here:h/bin to PATH, then try: ot-swiftc --version"
