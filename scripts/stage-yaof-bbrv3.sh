#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

OPENWRT_DIR="${1:-${OPENWRT_DIR:-}}"
[ -n "$OPENWRT_DIR" ] || die "Usage: $0 <openwrt-dir>"
need_dir "$OPENWRT_DIR"

YAOF_REPO_URL="${YAOF_REPO_URL:-https://github.com/QiuSimons/YAOF.git}"
YAOF_BBRV3_REF="${YAOF_BBRV3_REF:-25.12}"
YAOF_BBRV3_PATCH_DIR="${YAOF_BBRV3_PATCH_DIR:-PATCH/kernel/bbr3}"

kernel_patchver="$(
  awk -F ':=' '/^KERNEL_PATCHVER:=/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$OPENWRT_DIR/target/linux/rockchip/Makefile"
)"
[ -n "$kernel_patchver" ] || die "Unable to detect rockchip KERNEL_PATCHVER"

dst="$OPENWRT_DIR/target/linux/generic/backport-$kernel_patchver"
[ -d "$dst" ] || dst="$OPENWRT_DIR/target/linux/generic/backport"
need_dir "$dst"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

log "Fetching YAOF BBRv3 patches from $YAOF_REPO_URL ($YAOF_BBRV3_REF)"
git -C "$tmp_dir" init -q yaof
git -C "$tmp_dir/yaof" remote add origin "$YAOF_REPO_URL"
git -C "$tmp_dir/yaof" fetch --depth=1 origin "$YAOF_BBRV3_REF"
git -C "$tmp_dir/yaof" checkout -q --detach FETCH_HEAD

src="$tmp_dir/yaof/$YAOF_BBRV3_PATCH_DIR"
need_dir "$src"

patch_count="$(find "$src" -maxdepth 1 -type f -name '*.patch' | wc -l | tr -d '[:space:]')"
[ "$patch_count" -gt 0 ] || die "No BBRv3 patches found in $YAOF_BBRV3_PATCH_DIR"

log "Staging $patch_count YAOF BBRv3 patches into ${dst#$OPENWRT_DIR/}"
while IFS= read -r -d '' patch_file; do
  cp "$patch_file" "$dst/"
done < <(find "$src" -maxdepth 1 -type f -name '*.patch' -print0)
