#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE="$PROJECT_DIR/profiles/m28c/packages.txt"
SOURCES="$PROJECT_DIR/feeds/package-sources.conf"
PREPARE_SCRIPT="$PROJECT_DIR/scripts/prepare-packages.sh"
LEGACY_MARKER="$PROJECT_DIR/local-packages/mt5700webui-openwrt-server-main/.disabled"

fail() {
  printf '失败：%s\n' "$*" >&2
  exit 1
}

assert_profile_line() {
  local line="$1"
  grep -Fqx -- "$line" "$PROFILE" || fail "packages.txt 缺少: $line"
}

assert_source() {
  local name="$1"
  local repo="$2"
  local ref="$3"
  local destination="$4"
  local source_path="$5"

  awk \
    -v name="$name" \
    -v repo="$repo" \
    -v ref="$ref" \
    -v destination="$destination" \
    -v source_path="$source_path" '
      $1 == name &&
      $2 == repo &&
      $3 == ref &&
      $4 == destination &&
      $5 == source_path &&
      NF == 5 {
        found = 1
      }
      END {
        exit !found
      }
    ' "$SOURCES" || fail "package-sources.conf 中的 $name 定义不匹配"
}

for package in \
  luci-app-mt5700m \
  luci-i18n-mt5700m-zh-cn \
  ubus-at-daemon \
  sms-tool_q; do
  assert_profile_line "$package"
done

for package in \
  qmodem \
  luci-app-qmodem \
  luci-app-qmodem-next \
  luci-i18n-qmodem-next-zh-cn \
  sms-forwarder-next \
  modem_scan \
  tom_modem \
  qmodem_monitor \
  at-webserver \
  luci-app-at-webserver \
  luci-i18n-at-webserver-zh-cn; do
  assert_profile_line "-$package"
done

assert_source \
  mt5700m \
  https://github.com/FAN789/luci-app-mt5700m.git \
  88540743aa16d62476c058408d05055dc5c07fc5 \
  package/custom/luci-app-mt5700m \
  luci-app-mt5700m

for source_name in mt5700m-at-daemon mt5700m-sms-tool mt5700m-deps-version mt5700m-deps-license; do
  grep -Eq "^${source_name} https://github\\.com/FUjr/QModem\\.git 6f84b7935921cce6a215171af5e93cad62f8a5a5 " "$SOURCES" \
    || fail "QModem 固定依赖定义不匹配: $source_name"
done

if grep -Eq '^qmodem[[:space:]]' "$SOURCES"; then
  fail "仍在克隆完整 QModem 源码"
fi

[ -f "$LEGACY_MARKER" ] || fail "旧 MT5700 WebUI 缺少 .disabled 标记"
grep -Fq "remove_if_exists \"\$CUSTOM_DIR/qmodem\"" "$PREPARE_SCRIPT" \
  || fail "prepare-packages.sh 未清理旧 QModem 源码目录"
if grep -Fq 'customize_qmodem_menu' "$PREPARE_SCRIPT"; then
  fail "prepare-packages.sh 仍包含 QModem 菜单定制"
fi

printf 'MT5700M 软件包切换校验通过\n'
