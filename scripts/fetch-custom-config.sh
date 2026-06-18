#!/usr/bin/env bash

# 从私人仓库拉取 OpenWrt 配置文件
# 用法: fetch-custom-config.sh <openwrt-dir> <repo-url> [branch] [token]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=scripts/overlay-bin-common.sh
source "$SCRIPT_DIR/overlay-bin-common.sh"

OPENWRT_DIR="${1:-${OPENWRT_DIR:-}}"
REPO_URL="${2:-}"
BRANCH="${3:-main}"
TOKEN="${4:-${CUSTOM_CONFIG_TOKEN:-}}"

if [ -z "$OPENWRT_DIR" ] || [ -z "$REPO_URL" ]; then
  die "用法: $0 <openwrt-dir> <repo-url> [branch] [token]"
fi
need_dir "$OPENWRT_DIR"

PROJECT_DIR="${PROJECT_DIR:-$(project_dir)}"
TEMP_DIR="${OPENWRT_DIR}/.custom-config-temp"
CLONE_LOG="${OPENWRT_DIR}/.custom-config-clone.log"
DST_ROOT="${OPENWRT_DIR}/files"
USR_BIN_SRC=""
USR_BIN_DST="$DST_ROOT/usr/bin"

# ===== 主逻辑 =====

cleanup() {
  rm -rf "$TEMP_DIR"
  rm -f "$CLONE_LOG"
}
trap cleanup EXIT

# 清理旧的临时目录
[ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# 构建认证 URL
AUTH_REPO_URL="$REPO_URL"
DISPLAY_REPO_URL="$REPO_URL"
if [ -n "$TOKEN" ]; then
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::add-mask::%s\n' "$TOKEN"
  fi

  # 支持 HTTPS 令牌认证
  if [[ "$REPO_URL" == https://* ]]; then
    AUTH_REPO_URL="${REPO_URL#https://}"
    AUTH_REPO_URL="https://oauth2:${TOKEN}@${AUTH_REPO_URL}"
  fi
fi

# Clone 私人仓库
echo "正在从 $DISPLAY_REPO_URL (分支: $BRANCH) 拉取配置..."
if ! git clone --depth 1 --branch "$BRANCH" "$AUTH_REPO_URL" "$TEMP_DIR" >"$CLONE_LOG" 2>&1; then
  if [ -n "$TOKEN" ]; then
    grep -Fv -- "$TOKEN" "$CLONE_LOG" >&2 || true
  else
    cat "$CLONE_LOG" >&2 || true
  fi
  echo "错误: 拉取配置失败。请检查:"
  echo "  1. 仓库 URL 是否正确"
  echo "  2. 分支名称是否存在"
  echo "  3. 令牌是否有效（如果使用私有仓库）"
  exit 1
fi
rm -f "$CLONE_LOG"

# 自动检测仓库结构
# 支持两种结构：
# 1. 仓库有 files/ 目录：files/etc, files/usr 等
# 2. 仓库根目录直接包含配置：etc/, usr/, root/ 等任意目录结构
if [ -d "$TEMP_DIR/files" ]; then
  # 结构 1: 有 files/ 目录
  SRC_ROOT="$TEMP_DIR/files"
  echo "检测到仓库结构：使用 files/ 目录"
else
  # 结构 2: 仓库根目录直接是配置根（支持任意目录结构）
  SRC_ROOT="$TEMP_DIR"
  echo "检测到仓库结构：使用仓库根目录"
fi

# 确保目标目录存在
mkdir -p "$DST_ROOT"

# 确定 /usr/bin 源目录
if [ -d "$SRC_ROOT/usr/bin" ]; then
  USR_BIN_SRC="$SRC_ROOT/usr/bin"
fi

# ===== 合并配置文件 =====
echo "正在合并配置文件..."

# 从私人仓库复制文件到目标位置。
# prepare-overlay.sh 会先放置本地 files/，因此这里遇到已存在的目标文件时跳过，
# 以保留本地 overlay 的最高优先级。排除 /usr/bin（单独处理）。
find "$SRC_ROOT" -type f \
  ! -path '*/.git/*' \
  ! -path '*/usr/bin/*' \
  ! -name '.git*' \
  ! -name '.gitkeep' \
  ! -name 'README*' \
  ! -name 'LICENSE*' \
  ! -name '*.md' -print0 | while IFS= read -r -d '' src_file; do
  
  rel_path="${src_file#"$SRC_ROOT"/}"
  
  # 跳过仓库根目录直接的特殊文件（只在使用仓库根目录时）
  if [ "$SRC_ROOT" = "$TEMP_DIR" ]; then
    case "$rel_path" in
      .git*|README*|LICENSE*|*.md) continue ;;
    esac
  fi
  
  dst_file="$DST_ROOT/$rel_path"
  
  # 创建目标目录
  mkdir -p "$(dirname "$dst_file")"
  
  # 如果目标文件已存在（来自本地 files），跳过
  # 本地 files 目录优先级最高
  if [ -f "$dst_file" ]; then
    echo "跳过 $rel_path (本地文件优先级更高)"
  else
    cp "$src_file" "$dst_file"
    echo "添加 $rel_path"
  fi
done

# ===== 特殊处理 /usr/bin 目录 =====
if [ -n "$USR_BIN_SRC" ] && [ -d "$USR_BIN_SRC" ]; then
  echo "处理 /usr/bin 目录下的文件..."
  
  shopt -s nullglob dotglob
  for item in "$USR_BIN_SRC"/*; do
    base="$(basename "$item")"
    case "$base" in
      .gitkeep|README.md) continue ;;
    esac

    if [ -d "$item" ]; then
      # 如果本地 /usr/bin 已有此目录，跳过（本地优先）
      if [ ! -d "$USR_BIN_DST/$base" ]; then
        install_detected_binary "$item" "$base"
      else
        echo "跳过 /usr/bin/$base (本地版本优先级更高)"
      fi
    elif is_archive "$item"; then
      # 压缩包智能处理：解压后选择最合适的二进制
      preferred="$(strip_archive_ext "$base")"
      # 如果本地已有此文件，跳过
      if [ ! -f "$USR_BIN_DST/$preferred" ]; then
        tmp_dir="$(mktemp -d)"
        extract_archive "$item" "$tmp_dir"
        install_detected_binary "$tmp_dir" "$preferred"
        rm -rf "$tmp_dir"
      else
        echo "跳过 /usr/bin/$preferred (本地版本优先级更高)"
      fi
    elif [ -f "$item" ]; then
      # 如果本地已有此文件，跳过
      if [ ! -f "$USR_BIN_DST/$base" ]; then
        cp "$item" "$USR_BIN_DST/$base"
        chmod 0755 "$USR_BIN_DST/$base"
        log "安装 /usr/bin/$base (直接文件)"
      else
        echo "跳过 /usr/bin/$base (本地版本优先级更高)"
      fi
    else
      warn "忽略不支持的 /usr/bin 项: $item"
    fi
  done
  shopt -u nullglob dotglob
fi

echo "配置文件合并完成！"
