#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

OPENWRT_DIR="${1:-${OPENWRT_DIR:-}}"
[ -n "$OPENWRT_DIR" ] || die "用法: $0 <openwrt-dir>"
need_dir "$OPENWRT_DIR"

BBR_VERSION_PHASE="${BBR_VERSION_PHASE:-BBR 版本}"
BBR_VERSION_SOURCE_MODE="${BBR_VERSION_SOURCE_MODE:-auto}"
BBR_VERSION_RECORD_FILE="${BBR_VERSION_RECORD_FILE:-}"
BBR_VERSION_EXPECT_FILE="${BBR_VERSION_EXPECT_FILE:-}"
BBR_VERSION_FALLBACK="${BBR_VERSION_FALLBACK:-}"
BBR_VERSION_FALLBACK_SOURCE="${BBR_VERSION_FALLBACK_SOURCE:-回退值}"

kernel_patchver="$(
  awk -F ':=' '/^KERNEL_PATCHVER:=/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$OPENWRT_DIR/target/linux/rockchip/Makefile"
)"
[ -n "$kernel_patchver" ] || die "无法检测 rockchip KERNEL_PATCHVER"

patch_dirs=(
  "$OPENWRT_DIR/target/linux/generic/backport-$kernel_patchver"
  "$OPENWRT_DIR/target/linux/generic/backport"
  "$OPENWRT_DIR/target/linux/generic/hack-$kernel_patchver"
  "$OPENWRT_DIR/target/linux/generic/hack"
  "$OPENWRT_DIR/target/linux/generic/pending-$kernel_patchver"
  "$OPENWRT_DIR/target/linux/generic/pending"
)

detect_from_patch() {
  local dir="$1"
  local patch_file
  local version

  [ -d "$dir" ] || return 0

  while IFS= read -r -d '' patch_file; do
    version="$(
      sed -n 's/^[+[:space:]]*#define[[:space:]]\+BBR_VERSION[[:space:]]\+\([0-9]\+\).*/\1/p' "$patch_file" | head -n 1
    )"
    if [ -n "$version" ]; then
      printf '%s\t%s\n' "$version" "${patch_file#"$OPENWRT_DIR"/}"
      return 0
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.patch' -print0 | sort -z)
}

detect_from_source() {
  local source_file
  local version

  while IFS= read -r -d '' source_file; do
    version="$(
      sed -n 's/^[[:space:]]*#define[[:space:]]\+BBR_VERSION[[:space:]]\+\([0-9]\+\).*/\1/p' "$source_file" | head -n 1
    )"
    if [ -n "$version" ]; then
      printf '%s\t%s\n' "$version" "${source_file#"$OPENWRT_DIR"/}"
      return 0
    fi
  done < <(find "$OPENWRT_DIR/build_dir" -path '*/net/ipv4/tcp_bbr.c' -type f -print0 2>/dev/null || true)
}

result=""
case "$BBR_VERSION_SOURCE_MODE" in
  auto|patch)
    for dir in "${patch_dirs[@]}"; do
      result="$(detect_from_patch "$dir")"
      [ -z "$result" ] || break
    done
    ;;
  source) ;;
  *) die "不支持的 BBR_VERSION_SOURCE_MODE: $BBR_VERSION_SOURCE_MODE" ;;
esac

if [ -z "$result" ] && [ "$BBR_VERSION_SOURCE_MODE" != "patch" ]; then
  result="$(detect_from_source || true)"
fi

if [ -n "$result" ]; then
  detected_version="${result%%$'\t'*}"
  detected_source="${result#*$'\t'}"
elif [ -n "$BBR_VERSION_FALLBACK" ]; then
  detected_version="$BBR_VERSION_FALLBACK"
  detected_source="$BBR_VERSION_FALLBACK_SOURCE"
else
  detected_version="unknown"
  detected_source="未在已放置补丁或已准备内核源码中找到"
fi

cat <<EOF
========================================
阶段: $BBR_VERSION_PHASE
BBR_VERSION: $detected_version
来源: $detected_source
内核补丁版本: $kernel_patchver
========================================
EOF

if [ -n "$BBR_VERSION_RECORD_FILE" ]; then
  mkdir -p "$(dirname "$BBR_VERSION_RECORD_FILE")"
  printf '%s\t%s\n' "$detected_version" "$detected_source" > "$BBR_VERSION_RECORD_FILE"
fi

if [ -n "$BBR_VERSION_EXPECT_FILE" ]; then
  need_file "$BBR_VERSION_EXPECT_FILE"
  expected_line="$(head -n 1 "$BBR_VERSION_EXPECT_FILE")"
  expected_version="${expected_line%%$'\t'*}"
  expected_source="${expected_line#*$'\t'}"

  if [ "$detected_version" != "$expected_version" ]; then
    die "BBR_VERSION 不一致: 之前=$expected_version ($expected_source), 之后=$detected_version ($detected_source)"
  fi

  log "BBR_VERSION 与之前检测结果一致: $detected_version"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    printf '## %s\n\n' "$BBR_VERSION_PHASE"
    printf '| 项目 | 值 |\n'
    printf '| --- | --- |\n'
    printf "| BBR_VERSION | \`%s\` |\n" "$detected_version"
    printf "| 来源 | \`%s\` |\n" "$detected_source"
    printf "| 内核补丁版本 | \`%s\` |\n" "$kernel_patchver"
    if [ -n "${expected_version:-}" ]; then
      printf "| 上一次 BBR_VERSION | \`%s\` |\n" "$expected_version"
      printf "| 一致性 | \`%s\` |\n" "匹配"
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$detected_version" = "unknown" ]; then
  warn "未检测到 BBR_VERSION；该步骤仅提供信息，继续执行。"
else
  printf '::notice title=%s::BBR_VERSION=%s (%s)\n' "$BBR_VERSION_PHASE" "$detected_version" "$detected_source"
fi
