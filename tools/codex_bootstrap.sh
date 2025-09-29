#!/usr/bin/env bash
set -euo pipefail

# ---- Config you can tweak ----
NODE_VER="22.9.0"                  # portable Node version
REPO_DIR="/srv/collab"
NODE_DIR="$REPO_DIR/.node"         # portable Node lives here
CODEX_HOME_DIR="$REPO_DIR/.codex"  # Codex state lives here

# ---- Minimal deps (Debian/Ubuntu) ----
if ! command -v curl >/dev/null 2>&1 || ! command -v xz >/dev/null 2>&1; then
  echo "[bootstrap] Installing curl and xz-utils..."
  sudo apt-get update -y
  sudo apt-get install -y curl xz-utils
fi

# ---- Portable Node (per-arch) ----
mkdir -p "$NODE_DIR" "$CODEX_HOME_DIR"
if [[ ! -x "$NODE_DIR/bin/node" ]]; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    aarch64|arm64) NODE_TGZ="node-v${NODE_VER}-linux-arm64.tar.xz" ;;
    x86_64|amd64)  NODE_TGZ="node-v${NODE_VER}-linux-x64.tar.xz" ;;
    *) echo "Unsupported arch: $ARCH"; exit 1 ;;
  esac
  echo "[bootstrap] Fetching Node.js $NODE_VER for $ARCH..."
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "https://nodejs.org/dist/v${NODE_VER}/${NODE_TGZ}" -o "$tmp/node.txz"
  tar -xJf "$tmp/node.txz" -C "$NODE_DIR" --strip-components=1
fi

# ---- Run Codex via portable Node (no npm install) ----
export PATH="$NODE_DIR/bin:$PATH"
export CODEX_HOME="$CODEX_HOME_DIR"

echo "[bootstrap] Launching Codex CLI..."
exec npx -y @openai/codex@latest
