#!/bin/zsh
# Builds the MacroCheck package with the Xcode Overtime prepared, for macOS and for
# iOS devices, and lists the errors per file.
#
#   tests/macros/run.sh [--missing]
#
# --missing also compiles NewerOnly.swift, whose macros exist only in the newer Xcode
# and are expected to fail. DEVELOPER_DIR selects another Xcode.
set -euo pipefail
here=${0:A:h}
source "$here/../../lib/common.sh"
ot_load
xcode=${OT_PATCHED_XCODE:-${OT_XCODE_CLONE:-$OT_HOST_XCODE}}
export DEVELOPER_DIR=${DEVELOPER_DIR:-$xcode/Contents/Developer}
settings=()
[[ ${1:-} == --missing ]] && settings=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) MACROCHECK_MISSING')
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd "$here"
result=0
for destination in 'generic/platform=macOS' 'generic/platform=iOS'; do
    print "== $destination"
    if xcodebuild -scheme MacroCheck -destination "$destination" -derivedDataPath "$work/dd" \
            CODE_SIGNING_ALLOWED=NO $settings build > "$work/log" 2>&1; then
        print "ok"
    else
        grep -E 'error:' "$work/log" | sed -e "s#^$here/##" -e 's#^.*/Sources/#Sources/#' | sort -u || tail -20 "$work/log"
        result=1
    fi
done
exit $result
