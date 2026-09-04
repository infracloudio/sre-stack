#!/usr/bin/env bash
# Idempotent dev-environment bootstrap: installs every tool this repo's
# workflows need (make lint deps, k8s tooling, cloud CLIs), each only if
# missing — same check-then-create pattern as the provisioning scripts.
# DRY_RUN=1 reports what would be installed without touching the system.
# Linux (apt/dnf) and macOS (brew) supported. sudo is used where needed.
set -uo pipefail

DRY_RUN="${DRY_RUN:-0}"
OS="$(uname -s)"
ARCH="$(uname -m)"
# k8s-family assets use amd64/arm64; some vendors (aws cli) use x86_64/aarch64.
case "$ARCH" in
  x86_64) ARCH="amd64"; VENDOR_ARCH="x86_64" ;;
  aarch64 | arm64) ARCH="arm64"; VENDOR_ARCH="aarch64" ;;
esac
BIN_DIR="${HOME}/.local/bin"
KUSTOMIZE_VERSION="v5.3.0"
K3D_VERSION="v5.6.0"
SPEC_KIT_VERSION="v1.0.4"

have() { command -v "$1" >/dev/null 2>&1; }
as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}
run() {
  if [ "$DRY_RUN" = "1" ]; then echo "  [dry-run] $*"; else "$@"; fi
}

TOOLS=(jq shellcheck yamllint unzip kubectl helm kustomize k3d eksctl aws az uv specify)

missing=()
for tool in "${TOOLS[@]}"; do
  have "$tool" || missing+=("$tool")
done

echo "loom-of-the-day: ${#missing[@]} missing tool(s)"
[ "${#missing[@]}" -gt 0 ] && echo "  ${missing[*]}"
echo ""

pkg_install() {
  if [ "$OS" = "Darwin" ]; then
    run brew install "$@"
  elif have apt-get; then
    run as_root apt-get update -qq
    run as_root apt-get install -y -qq "$@"
  elif have dnf; then
    run as_root dnf install -y "$@"
  else
    echo "  ERROR: no supported package manager for $*" >&2
    return 1
  fi
}

fetch_bin() { # fetch_bin <url> <dest-file>
  local url="$1" dest="$2"
  run mkdir -p "$BIN_DIR"
  run curl -fsSL "$url" -o "$dest"
  run chmod +x "$dest"
}

install_tool() {
  local tool="$1"
  echo "== $tool =="
  case "$tool" in
    jq | shellcheck | yamllint | unzip)
      pkg_install "$tool"
      ;;
    kubectl)
      # Version query is read-only; safe outside the dry-run wrapper so the
      # previewed URL stays accurate.
      local ver
      if [ "$DRY_RUN" = "1" ]; then
        ver="<current-stable>"
      else
        ver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
      fi
      fetch_bin "https://dl.k8s.io/release/${ver}/bin/${OS,,}/${ARCH}/kubectl" \
        "$BIN_DIR/kubectl"
      ;;
    helm)
      run as_root bash -c \
        'curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'
      ;;
    kustomize)
      local os_name="linux"
      [ "$OS" = "Darwin" ] && os_name="darwin"
      run mkdir -p "$BIN_DIR"
      # Release tags are prefixed: kustomize/v5.3.0
      run curl -fsSL \
        "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_${os_name}_${ARCH}.tar.gz" \
        -o "/tmp/kustomize.tar.gz"
      run tar -xzf "/tmp/kustomize.tar.gz" -C "$BIN_DIR" kustomize
      run rm -f "/tmp/kustomize.tar.gz"
      ;;
    k3d)
      # install.sh takes no path flags: K3D_INSTALL_DIR env + internal runAsRoot.
      run curl -fsSL \
        "https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh" \
        -o "/tmp/k3d-install.sh"
      run as_root env TAG="${K3D_VERSION}" bash "/tmp/k3d-install.sh"
      run rm -f "/tmp/k3d-install.sh"
      ;;
    eksctl)
      local os_name="Linux"
      [ "$OS" = "Darwin" ] && os_name="Darwin"
      run mkdir -p "$BIN_DIR"
      run curl -fsSL \
        "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_${os_name}_${ARCH}.tar.gz" \
        -o "/tmp/eksctl.tar.gz"
      run tar -xzf "/tmp/eksctl.tar.gz" -C "$BIN_DIR" eksctl
      run rm -f "/tmp/eksctl.tar.gz"
      ;;
    aws)
      run mkdir -p "$BIN_DIR"
      run curl -fsSL "https://awscli.amazonaws.com/awscli-exe-${OS,,}-${VENDOR_ARCH}.zip" \
        -o "/tmp/awscli.zip"
      run unzip -q -o "/tmp/awscli.zip" -d /tmp
      run /tmp/aws/install -b "$BIN_DIR" -i "${HOME}/.local/aws-cli"
      run rm -rf /tmp/aws /tmp/awscli.zip
      ;;
    az)
      if [ "$OS" = "Darwin" ]; then
        run brew install azure-cli
      else
        run as_root bash -c 'curl -sL https://aka.ms/InstallAzureCLIDeb | bash'
      fi
      ;;
    uv)
      run bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
      ;;
    specify)
      # Spec Kit CLI — provides the `specify` binary behind the /speckit.*
      # workflow commands (AGENTS.md SDLC section). Pinned to a spec-kit
      # release tag; uv is its documented prerequisite.
      local uv_bin
      uv_bin="$(command -v uv || echo "$BIN_DIR/uv")"
      run "$uv_bin" tool install specify-cli \
        --from "git+https://github.com/github/spec-kit.git@${SPEC_KIT_VERSION}"
      ;;
    *)
      echo "  ERROR: no install recipe for $tool" >&2
      return 1
      ;;
  esac
}

failed=0
for tool in "${missing[@]}"; do
  if ! install_tool "$tool"; then
    failed=$((failed + 1))
  fi
done

if ! have docker; then
  echo ""
  echo "NOTE: docker is not installed — k3d (local mode) needs it."
  echo "      Install Docker Engine for your distro, then enable sudoless access:"
  echo "      https://docs.docker.com/engine/install/linux-postinstall/"
fi

if [ -d "$BIN_DIR" ] && ! echo "$PATH" | grep -q "$BIN_DIR"; then
  echo ""
  echo "NOTE: add $BIN_DIR to your PATH (kubectl/kustomize/aws/eksctl/specify install there):"
  echo "      export PATH=\"$BIN_DIR:\$PATH\""
fi

# Pre-commit hooks are compulsory: every harness and every human hits the
# same checks at commit time. Same as `make hooks`.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ "$DRY_RUN" != "1" ] && [ -n "$repo_root" ] && [ -d "$repo_root/.githooks" ]; then
  git -C "$repo_root" config core.hooksPath .githooks
  echo "pre-commit hooks enabled for this clone (core.hooksPath = .githooks)"
fi

if [ "$DRY_RUN" = "1" ]; then
  echo ""
  echo "DRY RUN complete — nothing was installed. Run 'make install' for real."
fi
exit "$failed"
