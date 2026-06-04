#!/usr/bin/env bash

# Shared helpers for staging executable files from overlay usr/bin directories.
# Callers should source scripts/common.sh first and set USR_BIN_DST before
# calling install_detected_binary. OVERLAY_BIN_NAME_MODE controls the output
# filename for detected binaries:
#   candidate  keep the chosen candidate basename, except generic names
#   preferred  always use the directory/archive-derived preferred name

strip_archive_ext() {
  local name="$1"
  case "$name" in
    *.tar.gz)  name="${name%.tar.gz}" ;;
    *.tar.xz)  name="${name%.tar.xz}" ;;
    *.tar.bz2) name="${name%.tar.bz2}" ;;
    *.tar.zst) name="${name%.tar.zst}" ;;
    *.tgz)     name="${name%.tgz}" ;;
    *.txz)     name="${name%.txz}" ;;
    *.tbz2)    name="${name%.tbz2}" ;;
    *.zip)     name="${name%.zip}" ;;
    *.gz)      name="${name%.gz}" ;;
    *.xz)      name="${name%.xz}" ;;
    *.zst)     name="${name%.zst}" ;;
  esac
  printf '%s\n' "$name"
}

is_archive() {
  local path="$1"
  case "${path,,}" in
    *.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.bz2|*.tbz2|*.tar.zst|*.zip|*.gz|*.xz|*.zst)
      return 0
      ;;
  esac
  return 1
}

extract_archive() {
  local archive="$1"
  local dest="$2"
  local base

  mkdir -p "$dest"
  case "${archive,,}" in
    *.tar.gz|*.tgz)     tar -xzf "$archive" -C "$dest" ;;
    *.tar.xz|*.txz)     tar -xJf "$archive" -C "$dest" ;;
    *.tar.bz2|*.tbz2)   tar -xjf "$archive" -C "$dest" ;;
    *.tar.zst)          tar --zstd -xf "$archive" -C "$dest" ;;
    *.tar)              tar -xf "$archive" -C "$dest" ;;
    *.zip)              unzip -q "$archive" -d "$dest" ;;
    *.gz)
      base="$(basename "${archive%.gz}")"
      gzip -dc "$archive" > "$dest/$base"
      ;;
    *.xz)
      base="$(basename "${archive%.xz}")"
      xz -dc "$archive" > "$dest/$base"
      ;;
    *.zst)
      base="$(basename "${archive%.zst}")"
      zstd -dc "$archive" > "$dest/$base"
      ;;
    *) die "Unsupported archive: $archive" ;;
  esac
}

candidate_score() {
  local file_path="$1"
  local preferred="$2"
  local info lower_path lower_base score

  info="$(file -b "$file_path" 2>/dev/null || true)"
  lower_path="${file_path,,}"
  lower_base="$(basename "$lower_path")"
  score=0

  case "$lower_base" in
    readme*|license*|copying*|*.md|*.txt|*.json|*.conf|*.service|*.desktop|*.png|*.jpg|*.jpeg|*.gif|*.svg)
      printf '%s\n' -999
      return
      ;;
  esac

  if [[ "$info" == *ELF* ]]; then
    score=$((score + 100))
    if [[ "${info,,}" == *aarch64* || "${info,,}" == *arm64* ]]; then
      score=$((score + 45))
    elif [[ "${info,,}" == *arm* ]]; then
      score=$((score + 20))
    fi
  elif head -c 2 "$file_path" 2>/dev/null | grep -q '^#!'; then
    score=$((score + 65))
  elif [[ "${info,,}" == *script* ]]; then
    score=$((score + 55))
  else
    printf '%s\n' -999
    return
  fi

  [[ "$lower_path" == *linux* ]] && score=$((score + 10))
  [[ "$lower_path" == *aarch64* || "$lower_path" == *arm64* ]] && score=$((score + 25))
  [[ "$lower_path" == *x86* || "$lower_path" == *amd64* || "$lower_path" == *windows* || "$lower_path" == *darwin* || "$lower_path" == *macos* ]] && score=$((score - 80))
  [[ "$lower_base" == "${preferred,,}" || "$lower_base" == "${preferred,,}"-* || "$lower_base" == "${preferred,,}"_* ]] && score=$((score + 35))
  [[ "$lower_base" != *.* ]] && score=$((score + 8))
  [ -x "$file_path" ] && score=$((score + 5))

  printf '%s\n' "$score"
}

install_detected_binary() {
  local search_dir="$1"
  local preferred="$2"
  local name_mode="${OVERLAY_BIN_NAME_MODE:-candidate}"
  local best=""
  local best_score=-999
  local file_path score dest_name

  [ -n "${USR_BIN_DST:-}" ] || die "USR_BIN_DST is not set"

  while IFS= read -r -d '' file_path; do
    score="$(candidate_score "$file_path" "$preferred")"
    if [ "$score" -gt "$best_score" ]; then
      best_score="$score"
      best="$file_path"
    fi
  done < <(find "$search_dir" -type f -print0)

  [ -n "$best" ] && [ "$best_score" -gt 0 ] || die "No executable binary/script found in $search_dir"

  case "$name_mode" in
    preferred)
      dest_name="$preferred"
      ;;
    candidate)
      dest_name="$(basename "$best")"
      case "$dest_name" in
        bin|linux|arm64|aarch64|release)
          dest_name="$preferred"
          ;;
      esac
      ;;
    *)
      die "Unsupported OVERLAY_BIN_NAME_MODE: $name_mode"
      ;;
  esac

  mkdir -p "$USR_BIN_DST"
  cp "$best" "$USR_BIN_DST/$dest_name"
  chmod 0755 "$USR_BIN_DST/$dest_name"
  log "Installed /usr/bin/$dest_name from ${best#$search_dir/}"
}
