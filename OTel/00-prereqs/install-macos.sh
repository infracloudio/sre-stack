#!/usr/bin/env bash
# Install the tools you need on macOS (MacBook Air). Idempotent — re-runs are safe.
set -euo pipefail

echo "==> Checking Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install from https://brew.sh first, then re-run." >&2
  exit 1
fi

echo "==> Installing Docker Desktop (if missing)"
# Docker Desktop is required for kind. If you already have OrbStack or colima,
# you can skip this — but the rest of the script assumes 'docker' resolves.
if ! command -v docker >/dev/null 2>&1; then
  brew install --cask docker
  echo "Docker installed. Open Docker Desktop once so its daemon starts, then re-run this script."
  exit 0
fi

echo "==> Installing CLI tools"
brew install kubectl helm kind k9s jq yq

echo "==> Versions"
docker --version
kubectl version --client --output=yaml | head -n 5
helm version --short
kind version
k9s version --short || true

echo
echo "Prerequisites OK. Next: ./01-cluster/up.sh"
