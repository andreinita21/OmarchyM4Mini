#!/bin/bash
# SPDX-License-Identifier: MIT
# build-j773g-dtbs.sh [linux-tree] — compile the Mac mini's device trees the
# way the packages and the boot ladder do, without building a kernel.
#
#   - the packaged DTB: Gravity's t8132-j773g.dts plus the PMU/poweroff and
#     headphone nodes linux-gravity-m4 adds (packaging/j773g/linux-gravity-m4)
#   - every boot-ladder rung from tools/j773g/inner-build.sh (BASE=gravity)
#
# Without a tree argument, the pinned GravityLinux/linux commit is fetched
# (device-tree paths only) into $TMPDIR. dtc warnings are shown, errors fail.
# CPP overrides the preprocessor (default cpp; "clang -E" on macOS).
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
PKG=$REPO/packaging/j773g/linux-gravity-m4
INNER=$REPO/tools/j773g/inner-build.sh
OUT=${OUT:-${TMPDIR:-/tmp}/j773g-dtbs}

# One Gravity pin for the package and the ladder build.
pkg_sha=$(sed -n 's/^_commit=\([0-9a-f]\{40\}\)$/\1/p' "$PKG/PKGBUILD")
ladder_sha=$(sed -n 's/.*GRAVITY_SHA:-\([0-9a-f]\{40\}\)}.*/\1/p' "$INNER")
[[ -n $pkg_sha && $pkg_sha == "$ladder_sha" ]] || {
  echo "Gravity pin differs: PKGBUILD $pkg_sha, inner-build.sh $ladder_sha" >&2
  exit 1
}

L=${1:-}
if [[ -z $L ]]; then
  L=${TMPDIR:-/tmp}/gravity-linux-$pkg_sha
  if [[ ! -d $L/.git ]]; then
    git init -q "$L"
    git -C "$L" sparse-checkout set --no-cone /arch/arm64/boot/dts/ \
      /include/dt-bindings/ /include/uapi/ /scripts/dtc/include-prefixes/
    git -C "$L" fetch -q --depth 1 --filter=blob:none \
      https://github.com/GravityLinux/linux.git "$pkg_sha"
  fi
  git -C "$L" -c advice.detachedHead=false checkout -q -f "$pkg_sha"
fi
APPLE=$L/arch/arm64/boot/dts/apple
[[ -f $APPLE/t8132-j773g.dts ]] || { echo "no t8132-j773g.dts in $L" >&2; exit 1; }

# Rung table: the [gN-name]="GROUPS" lines of the gravity case.
declare -A RUNGS=()
while IFS='=' read -r rung groups; do
  RUNGS[$rung]=${groups//\"/}
done < <(sed -n '/^  gravity)$/,/^    ;;$/s/^ *\[\(g[0-9]-[a-z0-9-]*\)\]=\(".*"\)$/\1=\2/p' "$INNER")
(( ${#RUNGS[@]} )) || { echo "no ladder rungs found in $INNER" >&2; exit 1; }

cp "$PKG"/t8132-j773g-pmu.dtsi "$PKG"/t8132-j773g-headphones.dtsi \
  "$REPO"/dts/t8132-j773g-ladder.dtsi "$APPLE/"
rm -rf "$OUT" && mkdir -p "$OUT"

dtb() {  # dtb <name> <source lines...>
  local name=$1; shift
  printf '%s\n' '// SPDX-License-Identifier: GPL-2.0+ OR MIT' "$@" > "$APPLE/ci-$name.dts"
  echo "=== $name"
  ${CPP:-cpp} -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
      -I "$L/include" -I "$L/arch/arm64/boot/dts" -I "$APPLE" \
      -I "$L/scripts/dtc/include-prefixes" "$APPLE/ci-$name.dts" |
    dtc -I dts -O dtb -o "$OUT/$name.dtb" -
}

# linux-gravity-m4 appends these two includes to the board file.
dtb t8132-j773g '#include "t8132-j773g.dts"' \
  '#include "t8132-j773g-pmu.dtsi"' '#include "t8132-j773g-headphones.dtsi"'
packaged=$(dtc -q -I dtb -O dts "$OUT/t8132-j773g.dtb")
for want in 'apple,j773g' 'apple,smc-reboot' 'apple,smc-rtc' 'cirrus,cs42l84'; do
  grep -q "\"$want\"" <<<"$packaged" || { echo "packaged DTB lacks $want" >&2; exit 1; }
done

for rung in $(printf '%s\n' "${!RUNGS[@]}" | sort); do
  lines=()
  for flag in ${RUNGS[$rung]}; do lines+=("#define J773G_LADDER_$flag"); done
  dtb "t8132-j773g-$rung" "${lines[@]}" \
    '#include "t8132-j773g.dts"' '#include "t8132-j773g-ladder.dtsi"'
done

echo
(cd "$OUT" && ls -1 ./*.dtb | wc -l | xargs echo "DTBs built:")
