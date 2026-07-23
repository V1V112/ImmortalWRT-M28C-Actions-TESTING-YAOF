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
    log "已移除冲突软件包路径: ${path#"$OPENWRT_DIR"/}"
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

# 清理旧版本由本脚本管理的完整 QModem 源码目录，避免复用构建树时残留。
remove_if_exists "$CUSTOM_DIR/qmodem"

declare -A SOURCE_CLONE_CACHE=()

clone_git_source() {
  local name="$1"
  local repo="$2"
  local ref="$3"
  local clone_dir="$4"
  local resolved_ref

  if [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
    log "正在克隆软件包源码: $name ($ref)"
    mkdir -p "$clone_dir"
    git -C "$clone_dir" init -q
    git -C "$clone_dir" remote add origin "$repo"

    if ! git -C "$clone_dir" fetch --depth 1 --filter=blob:none origin "$ref"; then
      warn "$name 的过滤抓取失败，将不使用 blob 过滤重试"
      rm -rf "$clone_dir"
      mkdir -p "$clone_dir"
      git -C "$clone_dir" init -q
      git -C "$clone_dir" remote add origin "$repo"
      git -C "$clone_dir" fetch --depth 1 origin "$ref"
    fi

    git -C "$clone_dir" checkout -q --detach FETCH_HEAD
    resolved_ref="$(git -C "$clone_dir" rev-parse HEAD)"
    [ "$resolved_ref" = "$ref" ] || die "$name 检出的提交不匹配: $resolved_ref"
    return 0
  fi

  log "正在克隆软件包源码: $name ($ref)"
  if ! git clone --depth 1 --filter=blob:none --branch "$ref" "$repo" "$clone_dir"; then
    warn "$name 的过滤克隆失败，将不使用 blob 过滤重试"
    rm -rf "$clone_dir"
    git clone --depth 1 --branch "$ref" "$repo" "$clone_dir"
  fi
}

clone_package_source() {
  local name="$1"
  local repo="$2"
  local ref="$3"
  local dest_rel="$4"
  local subdir="$5"
  local cache_key="${repo}|${ref}"
  local clone_dir
  local dest="$OPENWRT_DIR/$dest_rel"
  local src

  clone_dir="${SOURCE_CLONE_CACHE[$cache_key]:-}"
  if [ -n "$clone_dir" ]; then
    log "正在复用软件包源码: $name ($ref)"
  else
    clone_dir="$tmp_dir/$name"
    clone_git_source "$name" "$repo" "$ref" "$clone_dir"
    SOURCE_CLONE_CACHE["$cache_key"]="$clone_dir"
  fi

  if [ "$subdir" = "." ]; then
    src="$clone_dir"
  else
    src="$clone_dir/$subdir"
  fi

  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  if [ -d "$src" ]; then
    rsync -a --delete --exclude='.git' "$src"/ "$dest"/
  elif [ -f "$src" ]; then
    cp -a "$src" "$dest"
  else
    die "软件包源码路径不存在: $src"
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
    if [ -z "${repo:-}" ] || [ -z "${ref:-}" ] || [ -z "${dest:-}" ] || [ -z "${subdir:-}" ]; then
      die "$name 的软件包源码行无效"
    fi

    clone_package_source "$name" "$repo" "$ref" "$dest" "$subdir"
  done < "$PACKAGE_SOURCES"
fi

if [ "${SMARTDNS_PREBUILT_AUTO_UPDATE:-1}" != "0" ]; then
  log "正在把 smartdns-prebuilt 更新到 PikuZheng/smartdns 最新发布"
  bash "$SCRIPT_DIR/update-smartdns-prebuilt.sh" "$PROJECT_DIR/local-packages/smartdns-prebuilt/Makefile"
else
  log "已跳过 smartdns-prebuilt 自动更新"
fi

log "正在复制本地软件包源码"
shopt -s nullglob dotglob

copy_local_package() {
  local pkg="$1"
  local base

  base="$(basename "$pkg")"
  rm -rf "${LOCAL_DIR:?}/$base"
  rsync -a --delete --exclude='.git' "$pkg"/ "$LOCAL_DIR/$base"/
  log "已复制本地软件包: package/local/$base"
}

for pkg in "$PROJECT_DIR"/local-packages/*; do
  base="$(basename "$pkg")"
  case "$base" in
    .gitkeep|README.md) continue ;;
  esac

  if [ -d "$pkg" ]; then
    if [ -f "$pkg/.disabled" ]; then
      if [ -f "$pkg/Makefile" ]; then
        remove_if_exists "$LOCAL_DIR/$base"
      else
        for nested_pkg in "$pkg"/*; do
          [ -d "$nested_pkg" ] || continue
          [ -f "$nested_pkg/Makefile" ] || continue
          remove_if_exists "$LOCAL_DIR/$(basename "$nested_pkg")"
        done
      fi
      log "已跳过禁用的本地软件包源码: $base"
      continue
    fi

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
