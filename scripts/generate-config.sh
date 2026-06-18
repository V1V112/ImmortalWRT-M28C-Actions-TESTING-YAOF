#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

OPENWRT_DIR="${1:-${OPENWRT_DIR:-}}"
PROFILE_DIR="${2:-}"
if [ -z "$OPENWRT_DIR" ] || [ -z "$PROFILE_DIR" ]; then
  die "用法: $0 <openwrt-dir> <profile-dir>"
fi
need_dir "$OPENWRT_DIR"
need_dir "$PROFILE_DIR"

PROJECT_DIR="${PROJECT_DIR:-$(project_dir)}"
TARGET_CONFIG="$PROFILE_DIR/target.config"
PACKAGES_FILE="$PROFILE_DIR/packages.txt"
CUSTOM_CONFIG="$PROJECT_DIR/configs/custom.config"
OUT="$OPENWRT_DIR/.config"

need_file "$TARGET_CONFIG"
need_file "$PACKAGES_FILE"

emit_package_config() {
  local token="$1"
  local pkg

  token="${token//$'\r'/}"
  [ -n "$token" ] || return 0

  case "$token" in
    CONFIG_*=*)
      printf '%s\n' "$token"
      ;;
    \#*) return 0 ;;
    -*)
      pkg="${token#-}"
      [ -n "$pkg" ] && printf '# CONFIG_PACKAGE_%s is not set\n' "$pkg"
      ;;
    +*)
      pkg="${token#+}"
      [ -n "$pkg" ] && printf 'CONFIG_PACKAGE_%s=y\n' "$pkg"
      ;;
    *)
      printf 'CONFIG_PACKAGE_%s=y\n' "$token"
      ;;
  esac
}

emit_packages_from_text() {
  local line token
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line//$'\r'/}"
    case "$line" in
      "# CONFIG_"*" is not set")
        printf '%s\n' "$line"
        continue
        ;;
    esac
    line="${line%%#*}"
    for token in $line; do
      emit_package_config "$token"
    done
  done
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

{
  printf '# 由 scripts/generate-config.sh 生成\n\n'
  cat "$TARGET_CONFIG"
  printf '\n# 来自 %s 的软件包\n' "$PACKAGES_FILE"
  emit_packages_from_text < "$PACKAGES_FILE"

  if [ -n "${EXTRA_PACKAGES:-}" ]; then
    printf '\n# 来自工作流 extra_packages 的软件包\n'
    printf '%s\n' "$EXTRA_PACKAGES" | emit_packages_from_text
  fi

  if [ -f "$CUSTOM_CONFIG" ]; then
    printf '\n# 来自 configs/custom.config 的原始配置\n'
    cat "$CUSTOM_CONFIG"
  fi

  if [ -n "${EXTRA_CONFIG:-}" ]; then
    printf '\n# 来自工作流 extra_config 的原始配置\n'
    printf '%s\n' "$EXTRA_CONFIG"
    printf '\n'
  fi
} > "$tmp"

cp "$tmp" "$OUT"
log "已生成 $OUT"
