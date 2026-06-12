#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

OPENWRT_DIR="${1:-${OPENWRT_DIR:-}}"
[ -n "$OPENWRT_DIR" ] || die "Usage: $0 <openwrt-dir>"
need_dir "$OPENWRT_DIR"

TARGET_MK="$OPENWRT_DIR/include/target.mk"
need_file "$TARGET_MK"

ARCH_CFLAGS="${M28C_CFLAGS_ARCH:--march=armv8-a}"

log "Applying compile optimizations"
log "Replacing default -Os optimization with -O2 in include/target.mk"
sed -i -E 's/(^|[[:space:]])-Os([[:space:]]|$)/\1-O2\2/g' "$TARGET_MK"

if grep -q -- '-mcpu=generic' "$TARGET_MK"; then
  log "Replacing generic ARMv8 CPU flag with ${ARCH_CFLAGS}"
  sed -i "s,-mcpu=generic,${ARCH_CFLAGS},g" "$TARGET_MK"
else
  warn "No -mcpu=generic entry found in include/target.mk; architecture CFLAG unchanged"
fi

log "Compile optimizations applied"
