#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=scripts/overlay-bin-common.sh
source "$SCRIPT_DIR/overlay-bin-common.sh"

OPENWRT_DIR="${1:-${OPENWRT_DIR:-}}"
[ -n "$OPENWRT_DIR" ] || die "用法: $0 <openwrt-dir>"
need_dir "$OPENWRT_DIR"

PROJECT_DIR="${PROJECT_DIR:-$(project_dir)}"
SRC_ROOT="$PROJECT_DIR/files"
DST_ROOT="$OPENWRT_DIR/files"
USR_BIN_SRC="$SRC_ROOT/usr/bin"
USR_BIN_DST="$DST_ROOT/usr/bin"

stage_root_overlay() {
  [ -d "$SRC_ROOT" ] || return 0
  mkdir -p "$DST_ROOT"
  rsync -a \
    --exclude='.gitkeep' \
    --exclude='README.md' \
    --exclude='/usr/bin' \
    "$SRC_ROOT"/ "$DST_ROOT"/
}

stage_usr_bin() {
  local item base preferred tmp_dir

  [ -d "$USR_BIN_SRC" ] || return 0
  mkdir -p "$USR_BIN_DST"

  shopt -s nullglob dotglob
  for item in "$USR_BIN_SRC"/*; do
    base="$(basename "$item")"
    case "$base" in
      .gitkeep|README.md) continue ;;
    esac

    if [ -d "$item" ]; then
      install_detected_binary "$item" "$base"
    elif is_archive "$item"; then
      preferred="$(strip_archive_ext "$base")"
      tmp_dir="$(mktemp -d)"
      extract_archive "$item" "$tmp_dir"
      install_detected_binary "$tmp_dir" "$preferred"
      rm -rf "$tmp_dir"
    elif [ -f "$item" ]; then
      cp "$item" "$USR_BIN_DST/$base"
      chmod 0755 "$USR_BIN_DST/$base"
      log "已直接安装 /usr/bin/$base"
    else
      warn "忽略不支持的 /usr/bin overlay 条目: $item"
    fi
  done
}

log "正在把 rootfs overlay 放入 ImmortalWrt files/"
stage_root_overlay
stage_usr_bin
log "overlay 放置完成"
