#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

OPENWRT_DIR="${1:-${OPENWRT_DIR:-}}"
[ -n "$OPENWRT_DIR" ] || die "用法: $0 <openwrt-dir>"
need_dir "$OPENWRT_DIR"

PROJECT_DIR="${PROJECT_DIR:-$(project_dir)}"
PACKAGE_SOURCES="$PROJECT_DIR/feeds/package-sources.conf"
PACKAGES_TO_REMOVE="$PROJECT_DIR/feeds/packages-to-remove.conf"

CUSTOM_DIR="$OPENWRT_DIR/package/custom"
LOCAL_DIR="$OPENWRT_DIR/package/local"
mkdir -p "$CUSTOM_DIR" "$LOCAL_DIR"

remove_if_exists() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    rm -rf "$path"
    log "已移除冲突软件包路径: ${path#$OPENWRT_DIR/}"
  fi
}

remove_feed_package_defs() {
  local package_name="$1"
  local search_root makefile package_dir

  for search_root in "$OPENWRT_DIR/feeds" "$OPENWRT_DIR/package/feeds"; do
    [ -d "$search_root" ] || continue

    while IFS= read -r -d '' makefile; do
      grep -Eq "^(PKG_NAME:=${package_name}|define Package/${package_name}([[:space:]/]|$))" "$makefile" || continue
      package_dir="$(dirname "$makefile")"
      remove_if_exists "$package_dir"
    done < <(find "$search_root" -name Makefile -type f -print0)
  done
}

log "正在移除由第三方源码替换的内置软件包"
if [ -f "$PACKAGES_TO_REMOVE" ]; then
  while read -r package_name rest; do
    case "${package_name:-}" in
      ""|\#*) continue ;;
    esac
    
    [ -z "${rest:-}" ] || die "packages-to-remove 行无效: $package_name（应只包含软件包名称）"
    
    # 从常见 feed 路径移除
    remove_if_exists "$OPENWRT_DIR/feeds/packages/net/$package_name"
    remove_if_exists "$OPENWRT_DIR/feeds/luci/applications/$package_name"
    remove_if_exists "$OPENWRT_DIR/package/feeds/packages/$package_name"
    remove_if_exists "$OPENWRT_DIR/package/feeds/luci/$package_name"
    
    # 从 feeds 中移除软件包定义
    remove_feed_package_defs "$package_name"
  done < "$PACKAGES_TO_REMOVE"
else
  warn "未找到 packages-to-remove 配置，跳过软件包移除"
fi

clone_package_source() {
  local name="$1"
  local repo="$2"
  local ref="$3"
  local dest_rel="$4"
  local subdir="$5"
  local clone_dir="$tmp_dir/$name"
  local dest="$OPENWRT_DIR/$dest_rel"
  local src

  log "正在克隆软件包源码: $name ($ref)"
  if ! git clone --depth 1 --filter=blob:none --branch "$ref" "$repo" "$clone_dir"; then
    warn "$name 的过滤克隆失败，将不使用 blob 过滤重试"
    rm -rf "$clone_dir"
    git clone --depth 1 --branch "$ref" "$repo" "$clone_dir"
  fi

  if [ "$subdir" = "." ]; then
    src="$clone_dir"
  else
    src="$clone_dir/$subdir"
  fi

  need_dir "$src"
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  rsync -a --delete --exclude='.git' "$src"/ "$dest"/
}

customize_qmodem_menu() {
  local menu_file="$OPENWRT_DIR/package/custom/qmodem/luci/luci-app-qmodem-next/root/usr/share/luci/menu.d/luci-app-qmodem-next.json"

  [ -f "$menu_file" ] || return 0

  log "正在把 QModem LuCI 菜单移动到网络分类下"
  perl -0pi -e '
    s/\n\t"admin\/modem": \{.*?\n\t\},//s;
    s/"admin\/modem\/qmodem/"admin\/network\/qmodem/g;
    s/"title": "QModem"/"title": "调制解调器"/;
  ' "$menu_file"

  grep -q '"admin/network/qmodem"' "$menu_file" \
    || die "移动 QModem 菜单到网络分类失败"
  grep -q '"title": "调制解调器"' "$menu_file" \
    || die "重命名 QModem 菜单标题失败"
  if grep -q '"admin/modem' "$menu_file"; then
    die "QModem 菜单仍包含 admin/modem 条目"
  fi
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

if [ -f "$PACKAGE_SOURCES" ]; then
  while read -r name repo ref dest subdir rest; do
    case "${name:-}" in
      ""|\#*) continue ;;
    esac

    [ -z "${rest:-}" ] || die "$PACKAGE_SOURCES 中 $name 对应行的列数过多"
    [ -n "${repo:-}" ] && [ -n "${ref:-}" ] && [ -n "${dest:-}" ] && [ -n "${subdir:-}" ] \
      || die "$name 的软件包源码行无效"

    clone_package_source "$name" "$repo" "$ref" "$dest" "$subdir"
  done < "$PACKAGE_SOURCES"
fi

customize_qmodem_menu

log "正在复制本地软件包源码"
shopt -s nullglob dotglob

copy_local_package() {
  local pkg="$1"
  local base

  base="$(basename "$pkg")"
  rm -rf "$LOCAL_DIR/$base"
  rsync -a --delete --exclude='.git' "$pkg"/ "$LOCAL_DIR/$base"/
  log "已复制本地软件包: package/local/$base"
}

for pkg in "$PROJECT_DIR"/local-packages/*; do
  base="$(basename "$pkg")"
  case "$base" in
    .gitkeep|README.md) continue ;;
  esac

  if [ -d "$pkg" ]; then
    if [ -f "$pkg/Makefile" ]; then
      copy_local_package "$pkg"
      continue
    fi

    copied_nested=0
    for nested_pkg in "$pkg"/*; do
      [ -d "$nested_pkg" ] || continue
      [ -f "$nested_pkg/Makefile" ] || continue
      copy_local_package "$nested_pkg"
      copied_nested=1
    done

    [ "$copied_nested" -eq 1 ] || die "本地软件包目录中未找到 Makefile: $pkg"
  else
    warn "忽略非目录本地软件包条目: $pkg"
  fi
done

log "已在 package/custom 和 package/local 下准备好自定义软件包源码"
