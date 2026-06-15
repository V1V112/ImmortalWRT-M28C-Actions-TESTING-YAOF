#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

OPENWRT_DIR="${1:-${OPENWRT_DIR:-}}"
[ -n "$OPENWRT_DIR" ] || die "用法: $0 <openwrt-dir>"
need_dir "$OPENWRT_DIR"

PROJECT_DIR="${PROJECT_DIR:-$(project_dir)}"
FEEDS_CONF="$OPENWRT_DIR/feeds.conf.default"
need_file "$FEEDS_CONF"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

incoming="$tmp_dir/incoming.feeds"
: > "$incoming"

append_if_exists() {
  local file="$1"
  if [ -f "$file" ]; then
    cat "$file" >> "$incoming"
    printf '\n' >> "$incoming"
  fi
}

append_if_exists "$PROJECT_DIR/feeds/third-party.feeds"
append_if_exists "$PROJECT_DIR/feeds/custom.feeds"

if [ -n "${EXTRA_FEEDS:-}" ]; then
  printf '%s\n' "$EXTRA_FEEDS" >> "$incoming"
fi

log "正在合并第三方 feeds 到 feeds.conf.default"

cat "$FEEDS_CONF" "$incoming" | awk '
function trim(s) {
  sub(/^[[:space:]]+/, "", s)
  sub(/[[:space:]]+$/, "", s)
  return s
}
function repo_url(line, parts, url) {
  split(line, parts, /[[:space:]]+/)
  url = parts[3]
  sub(/;.*/, "", url)
  return url
}
{
  line = trim($0)
  if (line == "" || line ~ /^#/) next

  split(line, parts, /[[:space:]]+/)
  if (parts[1] !~ /^src-/ || parts[2] == "" || parts[3] == "") {
    print "跳过无效 feed 行: " line > "/dev/stderr"
    next
  }

  name = parts[2]
  url = repo_url(line)

  if (seen_name[name] || seen_url[url]) {
    print "跳过重复 feed: " line > "/dev/stderr"
    next
  }

  seen_name[name] = 1
  seen_url[url] = 1
  print line
}
' > "$tmp_dir/feeds.conf.default"

cp "$tmp_dir/feeds.conf.default" "$FEEDS_CONF"

log "最终 feeds:"
sed 's/^/  /' "$FEEDS_CONF"
