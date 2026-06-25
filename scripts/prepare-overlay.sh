#!/usr/bin/env bash

# OpenWrt 构建集成脚本
# 支持从私人仓库拉取配置并与本地 files 目录合并
# 
# 环境变量:
#   CUSTOM_CONFIG_REPO_URL: 私人配置仓库 URL (可选)
#   CUSTOM_CONFIG_BRANCH: 私人配置仓库分支，默认: main
#   CUSTOM_CONFIG_TOKEN: GitHub/Gitee Token，用于私有仓库认证 (可选)
#   CUSTOM_CONFIG_REQUIRED: 私人配置拉取失败时是否终止构建，默认: false
#
# 用法: prepare-overlay.sh <openwrt-dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

OPENWRT_DIR="${1:-${OPENWRT_DIR:-}}"
[ -n "$OPENWRT_DIR" ] || die "用法: $0 <openwrt-dir>"
need_dir "$OPENWRT_DIR"

PROJECT_DIR="${PROJECT_DIR:-$(project_dir)}"

# 先执行标准 overlay 阶段，让本地 files/ 成为明确的最高优先级。
log "执行标准 overlay 阶段..."
bash "$SCRIPT_DIR/stage-overlay.sh" "$OPENWRT_DIR"

# 从私人仓库拉取配置（可选），只补充本地 files/ 尚未提供的目标文件。
REPO_URL="${CUSTOM_CONFIG_REPO_URL:-}"
if [ -n "$REPO_URL" ]; then
  BRANCH="${CUSTOM_CONFIG_BRANCH:-main}"
  TOKEN="${CUSTOM_CONFIG_TOKEN:-}"
  REQUIRED="${CUSTOM_CONFIG_REQUIRED:-false}"
  
  log "从私人仓库拉取配置文件..."
  bash "$SCRIPT_DIR/fetch-custom-config.sh" "$OPENWRT_DIR" "$REPO_URL" "$BRANCH" "$TOKEN" || {
    case "${REQUIRED,,}" in
      1|true|yes|y)
        die "无法从私人仓库拉取配置，且 CUSTOM_CONFIG_REQUIRED=true"
        ;;
      *)
        warn "无法从私人仓库拉取配置，继续使用本地 files 目录"
        ;;
    esac
  }
fi

# 本地与私人仓库配置合并完成后，确保固件 /root 下的 shell 脚本可执行。
ROOT_HOME="$OPENWRT_DIR/files/root"
if [ -d "$ROOT_HOME" ]; then
  find "$ROOT_HOME" -type f -name '*.sh' -exec chmod a+x {} +
  log "已为 /root 下的 .sh 文件添加可执行权限"
fi

log "Overlay 准备完成"
