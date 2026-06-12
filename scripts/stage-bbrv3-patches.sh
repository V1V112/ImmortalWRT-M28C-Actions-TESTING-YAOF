#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

OPENWRT_DIR="${1:-${OPENWRT_DIR:-}}"
[ -n "$OPENWRT_DIR" ] || die "Usage: $0 <openwrt-dir>"
need_dir "$OPENWRT_DIR"

PROJECT_DIR="${PROJECT_DIR:-$(project_dir)}"
BBRV3_PATCH_ROOT="${BBRV3_PATCH_ROOT:-$PROJECT_DIR/patches/kernel/bbrv3}"
BBRV3_PATCH_SUBDIR="${BBRV3_PATCH_SUBDIR:-bbr3}"

kernel_patchver="$(
  awk -F ':=' '/^KERNEL_PATCHVER:=/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$OPENWRT_DIR/target/linux/rockchip/Makefile"
)"
[ -n "$kernel_patchver" ] || die "Unable to detect rockchip KERNEL_PATCHVER"

src="$BBRV3_PATCH_ROOT/kernel-$kernel_patchver/$BBRV3_PATCH_SUBDIR"
if [ ! -d "$src" ]; then
  available=""
  if [ -d "$BBRV3_PATCH_ROOT" ]; then
    for patch_dir in "$BBRV3_PATCH_ROOT"/kernel-*; do
      [ -d "$patch_dir" ] || continue
      version="${patch_dir##*/kernel-}"
      [ -n "$available" ] && available="$available, "
      available="$available$version"
    done
  fi
  [ -n "$available" ] || available="none"
  die "No local BBRv3 patch set for kernel $kernel_patchver under ${BBRV3_PATCH_ROOT#$PROJECT_DIR/}. Available kernel versions: $available"
fi

dst="$OPENWRT_DIR/target/linux/generic/backport-$kernel_patchver"
[ -d "$dst" ] || dst="$OPENWRT_DIR/target/linux/generic/backport"
need_dir "$dst"

patch_count="$(find "$src" -maxdepth 1 -type f -name '*.patch' | wc -l | tr -d '[:space:]')"
[ "$patch_count" -gt 0 ] || die "No BBRv3 patches found in ${src#$PROJECT_DIR/}"

log "Staging $patch_count local BBRv3 patches for kernel $kernel_patchver into ${dst#$OPENWRT_DIR/}"
while IFS= read -r -d '' patch_file; do
  cp "$patch_file" "$dst/"
done < <(find "$src" -maxdepth 1 -type f -name '*.patch' -print0 | sort -z)
