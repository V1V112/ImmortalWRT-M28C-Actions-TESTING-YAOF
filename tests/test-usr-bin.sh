#!/usr/bin/env bash

set -euo pipefail

if [ -z "${LC_ALL:-}" ] && command -v locale >/dev/null 2>&1; then
  if locale -a 2>/dev/null | grep -qi '^C\.UTF-8$'; then
    export LANG=C.UTF-8
    export LC_ALL=C.UTF-8
  elif locale -a 2>/dev/null | grep -qi '^C\.utf8$'; then
    export LANG=C.utf8
    export LC_ALL=C.utf8
  fi
fi

SCRIPT_ROOT_HINT="$(dirname "${BASH_SOURCE[0]}")/.."
if ROOT_DIR="$(git -C "$SCRIPT_ROOT_HINT" rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  ROOT_DIR="$(cd "$SCRIPT_ROOT_HINT" && pwd)"
fi
TMP_ROOT="$(mktemp -d)"

trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf '失败：%s\n' "$*" >&2
  exit 1
}

pass() {
  printf '通过：%s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少命令：$1"
}

assert_file() {
  [ -f "$1" ] || fail "预期文件不存在：$1"
}

assert_executable() {
  [ -x "$1" ] || fail "预期文件不可执行：$1"
}

assert_contains() {
  local file="$1"
  local expected="$2"

  grep -Fq -- "$expected" "$file" || fail "预期在 $file 中找到：$expected"
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"

  ! grep -Fq -- "$unexpected" "$file" || fail "不应在 $file 中找到：$unexpected"
}

new_case() {
  local name="$1"

  CASE_DIR="$TMP_ROOT/$name"
  CASE_PROJECT_DIR="$CASE_DIR/project"
  CASE_OPENWRT_DIR="$CASE_DIR/openwrt"
  CASE_LOG="$CASE_DIR/run.log"
  mkdir -p "$CASE_PROJECT_DIR" "$CASE_OPENWRT_DIR"
}

write_script() {
  local path="$1"
  local marker="$2"

  cat > "$path" <<EOF
#!/bin/sh
echo "$marker"
EOF
  chmod 0755 "$path"
}

run_stage_overlay() {
  if ! PROJECT_DIR="$CASE_PROJECT_DIR" \
    OVERLAY_BIN_NAME_MODE="${OVERLAY_BIN_NAME_MODE:-}" \
    bash "$ROOT_DIR/scripts/stage-overlay.sh" "$CASE_OPENWRT_DIR" >"$CASE_LOG" 2>&1; then
    cat "$CASE_LOG" >&2 || true
    return 1
  fi
}

run_prepare_overlay() {
  if ! PROJECT_DIR="$CASE_PROJECT_DIR" \
    OVERLAY_BIN_NAME_MODE="${OVERLAY_BIN_NAME_MODE:-}" \
    CUSTOM_CONFIG_REPO_URL="$REMOTE_REPO_DIR" \
    CUSTOM_CONFIG_BRANCH=main \
    bash "$ROOT_DIR/scripts/prepare-overlay.sh" "$CASE_OPENWRT_DIR" >"$CASE_LOG" 2>&1; then
    cat "$CASE_LOG" >&2 || true
    return 1
  fi
}

init_remote_repo() {
  local repo="$1"

  git init -q "$repo"
  git -C "$repo" checkout -q -B main
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "测试运行器"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "测试夹具"
}

test_stage_overlay_direct_file() {
  new_case "stage-direct-file"

  mkdir -p "$CASE_PROJECT_DIR/files/usr/bin"
  write_script "$CASE_PROJECT_DIR/files/usr/bin/direct-tool" "本地直接文件"

  run_stage_overlay

  local installed="$CASE_OPENWRT_DIR/files/usr/bin/direct-tool"
  assert_file "$installed"
  assert_executable "$installed"
  assert_contains "$installed" "本地直接文件"
  pass "stage-overlay 可安装 /usr/bin 直接文件"
}

test_stage_overlay_archive_preferred_name() {
  new_case "stage-archive"

  mkdir -p "$CASE_PROJECT_DIR/files/usr/bin" "$CASE_DIR/archive-src"
  write_script "$CASE_DIR/archive-src/packed-aarch64" "已选择 aarch64"
  write_script "$CASE_DIR/archive-src/packed-x86_64" "错误的 x86"
  printf '忽略我\n' > "$CASE_DIR/archive-src/README.txt"

  tar -czf "$CASE_PROJECT_DIR/files/usr/bin/packed.tar.gz" -C "$CASE_DIR/archive-src" .

  OVERLAY_BIN_NAME_MODE=preferred run_stage_overlay

  local installed="$CASE_OPENWRT_DIR/files/usr/bin/packed"
  assert_file "$installed"
  assert_executable "$installed"
  assert_contains "$installed" "已选择 aarch64"
  assert_not_contains "$installed" "错误的 x86"
  pass "stage-overlay 可解压压缩包并安装首选二进制"
}

test_prepare_overlay_preserves_local_priority() {
  new_case "prepare-local-priority"

  mkdir -p "$CASE_PROJECT_DIR/files/etc/config" "$CASE_PROJECT_DIR/files/usr/bin"
  printf '本地配置\n' > "$CASE_PROJECT_DIR/files/etc/config/network"
  write_script "$CASE_PROJECT_DIR/files/usr/bin/priority-tool" "本地优先"

  REMOTE_REPO_DIR="$CASE_DIR/remote-repo"
  mkdir -p "$REMOTE_REPO_DIR/files/etc/config" "$REMOTE_REPO_DIR/files/usr/bin"
  printf '远程配置\n' > "$REMOTE_REPO_DIR/files/etc/config/network"
  printf 'DHCP 配置\n' > "$REMOTE_REPO_DIR/files/etc/config/dhcp"
  write_script "$REMOTE_REPO_DIR/files/usr/bin/priority-tool" "远程优先"
  write_script "$REMOTE_REPO_DIR/files/usr/bin/remote-tool" "仅远程"
  init_remote_repo "$REMOTE_REPO_DIR"

  run_prepare_overlay

  assert_contains "$CASE_OPENWRT_DIR/files/etc/config/network" "本地配置"
  assert_not_contains "$CASE_OPENWRT_DIR/files/etc/config/network" "远程配置"
  assert_contains "$CASE_OPENWRT_DIR/files/etc/config/dhcp" "DHCP 配置"
  assert_contains "$CASE_OPENWRT_DIR/files/usr/bin/priority-tool" "本地优先"
  assert_not_contains "$CASE_OPENWRT_DIR/files/usr/bin/priority-tool" "远程优先"
  assert_contains "$CASE_OPENWRT_DIR/files/usr/bin/remote-tool" "仅远程"
  pass "prepare-overlay 合并私人配置时保留本地文件"
}

test_fetch_custom_config_remote_archive() {
  new_case "fetch-remote-archive"

  REMOTE_REPO_DIR="$CASE_DIR/remote-repo"
  mkdir -p "$REMOTE_REPO_DIR/files/usr/bin" "$CASE_DIR/remote-archive-src"
  write_script "$CASE_DIR/remote-archive-src/remote-packed-aarch64" "远程已选择"
  write_script "$CASE_DIR/remote-archive-src/remote-packed-amd64" "远程错误版本"
  tar -czf "$REMOTE_REPO_DIR/files/usr/bin/remote-packed.tar.gz" -C "$CASE_DIR/remote-archive-src" .
  init_remote_repo "$REMOTE_REPO_DIR"

  OVERLAY_BIN_NAME_MODE=preferred run_prepare_overlay

  local installed="$CASE_OPENWRT_DIR/files/usr/bin/remote-packed"
  assert_file "$installed"
  assert_executable "$installed"
  assert_contains "$installed" "远程已选择"
  assert_not_contains "$installed" "远程错误版本"
  pass "fetch-custom-config 可处理私人仓库 /usr/bin 压缩包"
}

main() {
  require_cmd bash
  require_cmd git
  require_cmd grep
  require_cmd tar
  require_cmd file
  require_cmd rsync

  test_stage_overlay_direct_file
  test_stage_overlay_archive_preferred_name
  test_prepare_overlay_preserves_local_priority
  test_fetch_custom_config_remote_archive
}

main "$@"
