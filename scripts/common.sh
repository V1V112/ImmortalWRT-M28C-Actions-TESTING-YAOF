#!/usr/bin/env bash

set -euo pipefail

project_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

log() {
  printf '\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m警告:\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2
  exit 1
}

need_dir() {
  local dir="$1"
  [ -d "$dir" ] || die "目录不存在: $dir"
}

need_file() {
  local file="$1"
  [ -f "$file" ] || die "文件不存在: $file"
}
