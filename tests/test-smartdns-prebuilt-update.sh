#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
tmp_dir="$(mktemp -d)"
server_pid=""

cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

makefile="$tmp_dir/Makefile"
port_file="$tmp_dir/port"

cat > "$makefile" <<'EOF'
PKG_VERSION:=0
PKG_RELEASE:=9
SMARTDNS_UPSTREAM_VERSION:=0
SMARTDNS_RELEASE_TAG:=old
SMARTDNS_PREBUILT_HASH:=old
EOF

python3 - "$port_file" <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

port_file = sys.argv[1]


def release(tag, asset_name=None):
    assets = []
    if asset_name:
        assets.append({
            "name": asset_name,
            "browser_download_url": "https://invalid.example/unused.ipk",
            "digest": "sha256:" + "a" * 64,
        })
    return {"tag_name": tag, "draft": False, "prerelease": False, "assets": assets}


class Handler(BaseHTTPRequestHandler):
    request_count = 0

    def do_GET(self):
        request = urlparse(self.path)
        page = int(parse_qs(request.query).get("page", ["1"])[0])
        if request.path.endswith("/releases/latest"):
            payload = release("regular-latest")
        elif page == 1:
            payload = [release(f"regular-{index}") for index in range(30)]
        elif page == 2:
            payload = [release(
                "1.2026.v48.3.0_with_ui",
                "smartdns_with_ui.1.2026.v48.3.0.aarch64.ipk",
            )]
        else:
            payload = []

        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

        Handler.request_count += 1
        if Handler.request_count == 3:
            self.server.shutdown()

    def log_message(self, _format, *_args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as output:
    output.write(str(server.server_port))
server.serve_forever()
PY
server_pid=$!

for _ in {1..50}; do
  [ -s "$port_file" ] && break
  sleep 0.1
done
[ -s "$port_file" ] || { echo "测试 API 服务启动失败" >&2; exit 1; }

SMARTDNS_PREBUILT_API_ROOT="http://127.0.0.1:$(cat "$port_file")" \
SMARTDNS_PREBUILT_REPO="mock/smartdns" \
  bash "$PROJECT_DIR/scripts/update-smartdns-prebuilt.sh" "$makefile"

grep -qx 'PKG_VERSION:=1.2026.48.3.0' "$makefile"
grep -qx 'PKG_RELEASE:=1' "$makefile"
grep -qx 'SMARTDNS_UPSTREAM_VERSION:=1.2026.v48.3.0' "$makefile"
grep -qx 'SMARTDNS_RELEASE_TAG:=1.2026.v48.3.0_with_ui' "$makefile"
grep -qx "SMARTDNS_PREBUILT_HASH:=$(printf 'a%.0s' {1..64})" "$makefile"

echo "smartdns-prebuilt latest 与分页回退测试通过"
