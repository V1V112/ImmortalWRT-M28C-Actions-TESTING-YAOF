#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

PROJECT_DIR="${PROJECT_DIR:-$(project_dir)}"
MAKEFILE_PATH="${1:-$PROJECT_DIR/local-packages/smartdns-prebuilt/Makefile}"

need_file "$MAKEFILE_PATH"

python3 - "$MAKEFILE_PATH" <<'PY'
import hashlib
import json
import os
import re
import sys
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

makefile_path = Path(sys.argv[1])
repo = os.environ.get("SMARTDNS_PREBUILT_REPO", "PikuZheng/smartdns")
arch = os.environ.get("SMARTDNS_PREBUILT_ARCH", "aarch64")
include_prerelease = os.environ.get("SMARTDNS_PREBUILT_ALLOW_PRERELEASE", "0") == "1"
api_root = os.environ.get("SMARTDNS_PREBUILT_API_ROOT", "https://api.github.com").rstrip("/")
releases_per_page = 30
max_release_pages = 10
asset_re = re.compile(rf"^smartdns_with_ui\.(?P<version>.+)\.{re.escape(arch)}\.ipk$")

headers = {
    "Accept": "application/vnd.github+json",
    "User-Agent": "ImmortalWRT-M28C-smartdns-prebuilt-updater",
}
token = os.environ.get("GITHUB_TOKEN")
if token:
    headers["Authorization"] = f"Bearer {token}"


def fetch_json(url):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as response:
        return json.load(response)


def sha256_from_url(url):
    req = urllib.request.Request(url, headers=headers)
    sha256 = hashlib.sha256()
    with urllib.request.urlopen(req, timeout=180) as response:
        with tempfile.TemporaryFile() as tmp:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                sha256.update(chunk)
                tmp.write(chunk)
    return sha256.hexdigest()


def package_version(upstream_version):
    value = re.sub(r"(^|[._-])v(?=\d)", r"\1", upstream_version, flags=re.IGNORECASE)
    value = re.sub(r"[^0-9._-]+", ".", value)
    value = re.sub(r"[._-]+", ".", value).strip(".-_")
    if not value or not value[0].isdigit():
        value = f"0.{value}" if value else "0"
    return value


def set_var(text, name, value):
    pattern = re.compile(rf"^{re.escape(name)}:=.*$", re.MULTILINE)
    replacement = f"{name}:={value}"
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise SystemExit(f"未在 {makefile_path} 中找到变量 {name}")
    return text


def select_asset(release):
    if release.get("draft"):
        return None
    if release.get("prerelease") and not include_prerelease:
        return None
    for asset in release.get("assets", []):
        match = asset_re.match(asset.get("name", ""))
        if match:
            return release, asset, match.group("version")
    return None


# PikuZheng/smartdns may return an empty releases collection even though its
# designated latest release is available, so query that endpoint first.
latest_release = fetch_json(f"{api_root}/repos/{repo}/releases/latest")
if not isinstance(latest_release, dict):
    raise SystemExit(f"{repo} latest release API 返回了无效数据")

selected = select_asset(latest_release)
pages_checked = 0
for page in range(1, max_release_pages + 1) if not selected else ():
    query = urllib.parse.urlencode({"per_page": releases_per_page, "page": page})
    releases = fetch_json(f"{api_root}/repos/{repo}/releases?{query}")
    if not isinstance(releases, list):
        raise SystemExit(f"{repo} releases API 返回了无效数据")

    pages_checked = page
    for release in releases:
        selected = select_asset(release)
        if selected:
            break
    if selected:
        break
    if len(releases) < releases_per_page:
        break

if not selected:
    raise SystemExit(
        f"未在 {repo} 的 latest release 及最近 {pages_checked} 页发布中找到 "
        f"smartdns_with_ui.*.{arch}.ipk 资产"
    )

release, asset, upstream_version = selected
tag = release["tag_name"]
digest = asset.get("digest") or ""
if digest.startswith("sha256:"):
    sha256 = digest.removeprefix("sha256:")
else:
    sha256 = sha256_from_url(asset["browser_download_url"])

text = makefile_path.read_text(encoding="utf-8")
text = set_var(text, "PKG_VERSION", package_version(upstream_version))
text = set_var(text, "PKG_RELEASE", "1")
text = set_var(text, "SMARTDNS_UPSTREAM_VERSION", upstream_version)
text = set_var(text, "SMARTDNS_RELEASE_TAG", tag)
text = set_var(text, "SMARTDNS_PREBUILT_HASH", sha256)
makefile_path.write_text(text, encoding="utf-8", newline="\n")

print(f"smartdns-prebuilt: 已更新为 {repo} {tag} {asset['name']} sha256={sha256}")
PY
