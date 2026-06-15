#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

OPENWRT_DIR="${1:-${OPENWRT_DIR:-}}"
[ -n "$OPENWRT_DIR" ] || die "用法: $0 <openwrt-dir>"
need_dir "$OPENWRT_DIR"

TARGET_MK="$OPENWRT_DIR/include/target.mk"
need_file "$TARGET_MK"

ARCH_CFLAGS="${M28C_CFLAGS_ARCH:--march=armv8-a}"

log "正在应用编译优化"
log "正在把 include/target.mk 中的默认 -Os 优化替换为 -O2"
sed -i -E 's/(^|[[:space:]])-Os([[:space:]]|$)/\1-O2\2/g' "$TARGET_MK"

if grep -q -- '-mcpu=generic' "$TARGET_MK"; then
  log "正在把 generic ARMv8 CPU 参数替换为 ${ARCH_CFLAGS}"
  sed -i "s,-mcpu=generic,${ARCH_CFLAGS},g" "$TARGET_MK"
else
  warn "include/target.mk 中未找到 -mcpu=generic 条目；架构 CFLAG 保持不变"
fi

log "编译优化已应用"
