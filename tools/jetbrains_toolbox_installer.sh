#!/bin/bash

API_URL='https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release'
INSTALL_ROOT="${HOME}/.local/share/JetBrains/Toolbox"
BIN_DIR="${HOME}/.local/bin"

# Ensure jq & curl (only if apt is available)
if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -qq
    sudo apt-get install -y -qq jq curl ca-certificates tar coreutils >/dev/null
  else
    log "Missing jq/curl; install them and re-run." >&2
    exit 1
  fi
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

arch="$(dpkg --print-architecture || true)"
dl_key="linux"; [[ "$arch" == "arm64" ]] && { dl_key="linuxARM64"; export LIBGL_ALWAYS_SOFTWARE=1; }

json="$(curl -fsSL --retry 5 --retry-connrefused "$API_URL")"
url="$(jq -r ".TBA[0].downloads.${dl_key}.link" <<<"$json")"
sum_url="$(jq -r ".TBA[0].downloads.${dl_key}.checksumLink" <<<"$json")"
version="$(jq -r '.TBA[0].build' <<<"$json")"

[[ -n "$url" && "$url" != "null" ]] || { log "No Linux download found." >&2; exit 1; }

file="$tmp/$(basename "$url")"
dest="${INSTALL_ROOT}/${version}"

log "Downloading JetBrains Toolbox ${version}..."
curl -fL --retry 5 --retry-connrefused -o "$file" "$url"

# Verify checksum when provided
if [[ -n "$sum_url" && "$sum_url" != "null" ]]; then
  log "Verifying checksum..."
  curl -fL --retry 5 --retry-connrefused -o "${file}.sha256" "$sum_url"
  if ! grep -q "${file##*/}$" "${file}.sha256"; then
    sum="$(sed 's/[[:space:]].*$//' "${file}.sha256")"
    printf "%s  %s\n" "$sum" "${file##*/}" > "${file}.sha256"
  fi
  (cd "$tmp" && sha256sum -c "${file}.sha256")
fi

log "Installing to ${dest}..."
work="$tmp/extract"; mkdir -p "$work"
tar -xzf "$file" -C "$work"

# Find the actual binary regardless of archive nesting
bin_path="$(find "$work" -type f -name jetbrains-toolbox -print -quit || true)"
[[ -n "$bin_path" ]] || { log "Binary not found after extraction."; find "$work" -maxdepth 2 -print; exit 1; }

src_dir="$(dirname "$bin_path")"     # the folder that contains the binary

rm -rf "$dest"; mkdir -p "$dest"
# Copy that folder’s contents into the install dir
tar -C "$src_dir" -cf - . | tar -C "$dest" -xf -

chmod +x "${dest}/jetbrains-toolbox"
ln -sfn "$dest" "${INSTALL_ROOT}/current"

mkdir -p "$BIN_DIR"
ln -sfn "${INSTALL_ROOT}/current/jetbrains-toolbox" "${BIN_DIR}/jetbrains-toolbox"

log "Done. jetbrains-toolbox → ${BIN_DIR}/jetbrains-toolbox"
case ":$PATH:" in *":${BIN_DIR}:"*) ;; *) log "Hint: add to PATH → export PATH=\"${BIN_DIR}:\$PATH\"";; esac