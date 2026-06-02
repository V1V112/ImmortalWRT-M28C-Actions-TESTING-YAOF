#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

OPENWRT_DIR="${1:-${OPENWRT_DIR:-}}"
[ -n "$OPENWRT_DIR" ] || die "Usage: $0 <openwrt-dir>"
need_dir "$OPENWRT_DIR"

BBR_VERSION_PHASE="${BBR_VERSION_PHASE:-BBR Version}"
BBR_VERSION_SOURCE_MODE="${BBR_VERSION_SOURCE_MODE:-auto}"
BBR_VERSION_RECORD_FILE="${BBR_VERSION_RECORD_FILE:-}"
BBR_VERSION_EXPECT_FILE="${BBR_VERSION_EXPECT_FILE:-}"

kernel_patchver="$(
  awk -F ':=' '/^KERNEL_PATCHVER:=/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$OPENWRT_DIR/target/linux/rockchip/Makefile"
)"
[ -n "$kernel_patchver" ] || die "Unable to detect rockchip KERNEL_PATCHVER"

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
      printf '%s\t%s\n' "$version" "${patch_file#$OPENWRT_DIR/}"
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
      printf '%s\t%s\n' "$version" "${source_file#$OPENWRT_DIR/}"
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
  *) die "Unsupported BBR_VERSION_SOURCE_MODE: $BBR_VERSION_SOURCE_MODE" ;;
esac

if [ -z "$result" ] && [ "$BBR_VERSION_SOURCE_MODE" != "patch" ]; then
  result="$(detect_from_source || true)"
fi

if [ -n "$result" ]; then
  detected_version="${result%%$'\t'*}"
  detected_source="${result#*$'\t'}"
else
  detected_version="unknown"
  detected_source="not found in staged patches or prepared kernel source"
fi

cat <<EOF
========================================
Phase: $BBR_VERSION_PHASE
BBR_VERSION: $detected_version
Source: $detected_source
Kernel patch version: $kernel_patchver
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
    die "BBR_VERSION mismatch: before=$expected_version ($expected_source), after=$detected_version ($detected_source)"
  fi

  log "BBR_VERSION is consistent with previous detection: $detected_version"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    printf '## %s\n\n' "$BBR_VERSION_PHASE"
    printf '| Item | Value |\n'
    printf '| --- | --- |\n'
    printf '| BBR_VERSION | `%s` |\n' "$detected_version"
    printf '| Source | `%s` |\n' "$detected_source"
    printf '| Kernel patch version | `%s` |\n' "$kernel_patchver"
    if [ -n "${expected_version:-}" ]; then
      printf '| Previous BBR_VERSION | `%s` |\n' "$expected_version"
      printf '| Consistency | `%s` |\n' "matched"
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$detected_version" = "unknown" ]; then
  warn "BBR_VERSION was not detected; continuing because this step is informational."
else
  printf '::notice title=%s::BBR_VERSION=%s (%s)\n' "$BBR_VERSION_PHASE" "$detected_version" "$detected_source"
fi
