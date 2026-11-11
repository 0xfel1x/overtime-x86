#!/bin/zsh
# Regenerates App/Overtime.icns from scripts/make-icon.swift. Only needed after
# changing the drawing; the resulting .icns is committed.
set -euo pipefail
source "${0:A:h}/../lib/common.sh"
[[ -d $OT_HOST_XCODE/Contents/Developer ]] && export DEVELOPER_DIR="$OT_HOST_XCODE/Contents/Developer"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
xcrun swift "$OT_ROOT/scripts/make-icon.swift" "$work/icon.png"
set_dir="$work/Overtime.iconset"
mkdir "$set_dir"
for s in 16 32 128 256 512; do
    sips -z $s $s "$work/icon.png" --out "$set_dir/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$work/icon.png" --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o "$OT_ROOT/App/Overtime.icns"
[[ -n ${1:-} ]] && cp "$work/icon.png" "$1"
ot_info "wrote $OT_ROOT/App/Overtime.icns"
