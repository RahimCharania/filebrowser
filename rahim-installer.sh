#!/usr/bin/env bash
set -euo pipefail

ROOT_SHARE="${1:-}"
if [[ -z "${ROOT_SHARE}" ]]; then
  echo "usage: $0 <root_share_path>"
  echo "example: $0 /shared"
  exit 2
fi

if [[ "$(id -u)" != "0" ]]; then
  echo "error: must run as root"
  exit 1
fi

if [[ ! -d "${ROOT_SHARE}" ]]; then
  echo "error: root share path does not exist: ${ROOT_SHARE}"
  exit 1
fi

FB_PORT="${FB_PORT:-8080}"
FB_ADMIN_USER="${FB_ADMIN_USER:-admin}"
FB_ADMIN_PASSWORD="${FB_ADMIN_PASSWORD:-}"

need_cmd() { command -v "$1" >/dev/null 2>&1; }

if ! need_cmd curl; then
  apt-get update -y
  apt-get install -y curl
fi

if ! need_cmd systemctl; then
  echo "error: systemd/systemctl not found; this installer expects a systemd-based system"
  exit 1
fi

if [[ -z "${FB_ADMIN_PASSWORD}" ]]; then
  if need_cmd openssl; then
    FB_ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-24)"
  else
    apt-get update -y
    apt-get install -y openssl
    FB_ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-24)"
  fi
fi

arch="$(uname -m)"
case "${arch}" in
  x86_64|amd64) asset_arch="amd64" ;;
  aarch64|arm64) asset_arch="arm64" ;;
  armv7l) asset_arch="armv7" ;;
  armv6l) asset_arch="armv6" ;;
  *)
    echo "error: unsupported arch for prebuilt binary: ${arch}"
    exit 1
    ;;
esac

tag="${FB_TAG:-}"
if [[ -z "${tag}" ]]; then
  # Best-effort fetch of the latest release tag. If GitHub API is unavailable/rate-limited,
  # fall back to the known-good tag used on platform-001a.
  tag="$(curl -fsSL https://api.github.com/repos/gtsteffaniak/filebrowser/releases/latest 2>/dev/null \
    | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1 || true)"
  tag="${tag:-v1.1.2-stable}"
fi

asset="linux-${asset_arch}-filebrowser"
url="https://github.com/gtsteffaniak/filebrowser/releases/download/${tag}/${asset}"

install -d /opt/filebrowser-bin
curl -fsSL -o /opt/filebrowser-bin/filebrowser "${url}"
chmod +x /opt/filebrowser-bin/filebrowser

install -m 0755 /opt/filebrowser-bin/filebrowser /usr/local/bin/filebrowser-quantum
ln -sf /usr/local/bin/filebrowser-quantum /usr/local/bin/filebrowser

install -d /etc/filebrowser /var/lib/filebrowser "${ROOT_SHARE}/.filebrowser-cache"

cat >/etc/filebrowser/config.yaml <<YAML
server:
  port: ${FB_PORT}
  baseURL: "/"
  database: "/var/lib/filebrowser/database.db"
  cacheDir: "${ROOT_SHARE}/.filebrowser-cache"
  sources:
    - path: "${ROOT_SHARE}"
auth:
  adminUsername: "${FB_ADMIN_USER}"
  adminPassword: "${FB_ADMIN_PASSWORD}"
  methods:
    password:
      enabled: true
YAML

cat >/etc/systemd/system/filebrowser-quantum.service <<'UNIT'
[Unit]
Description=FileBrowser Quantum
After=network-online.target remote-fs.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/filebrowser-quantum -c /etc/filebrowser/config.yaml
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now filebrowser-quantum.service

echo
echo "Installed FileBrowser Quantum:"
echo "- Tag: ${tag}"
echo "- Root: ${ROOT_SHARE}"
echo "- URL: http://<this-host>:${FB_PORT}/"
echo "- Login: ${FB_ADMIN_USER}:${FB_ADMIN_PASSWORD}"
