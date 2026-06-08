#!/bin/sh
# boxsh installer — download the latest release binary for your platform.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/chenwanz/boxsh/master/install.sh | sh
#
# Options (via environment variables):
#   BOXSH_REPO      — GitHub repository (default: chenwanz/boxsh)
#   BOXSH_VERSION   — specific version tag (default: latest)
#   BOXSH_INSTALL   — installation directory (default: /usr/local/bin)
#   BOXSH_SKIP_CHECKSUM=1 — skip release checksum verification

set -e

REPO="${BOXSH_REPO:-chenwanz/boxsh}"
INSTALL_DIR="${BOXSH_INSTALL:-/usr/local/bin}"

# Detect OS
OS="$(uname -s)"
case "$OS" in
    Linux)  OS_TAG="linux" ;;
    Darwin) OS_TAG="darwin" ;;
    *)      echo "Error: unsupported OS: $OS" >&2; exit 1 ;;
esac

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64)   ARCH_TAG="x64" ;;
    i686|i386)       ARCH_TAG="ia32" ;;
    aarch64|arm64)   ARCH_TAG="arm64" ;;
    armv7l|armhf)    ARCH_TAG="arm" ;;
    mips64*)         ARCH_TAG="mips64" ;;
    ppc64le)         ARCH_TAG="ppc64" ;;
    riscv64)         ARCH_TAG="riscv64" ;;
    loongarch64)     ARCH_TAG="loong64" ;;
    *)               echo "Error: unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

# macOS uses different arch tags in uname vs release
if [ "$OS_TAG" = "darwin" ] && [ "$ARCH_TAG" = "x64" ]; then
    ARCH_TAG="x86_64"
fi

# Resolve version
if [ -z "$BOXSH_VERSION" ]; then
    BOXSH_VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"//;s/".*//')"
    if [ -z "$BOXSH_VERSION" ]; then
        echo "Error: failed to determine latest version" >&2
        exit 1
    fi
fi

FILENAME="boxsh-${BOXSH_VERSION}-${OS_TAG}-${ARCH_TAG}"
URL="https://github.com/${REPO}/releases/download/${BOXSH_VERSION}/${FILENAME}"
CHECKSUM_URL="${URL}.sha256"

echo "Installing boxsh ${BOXSH_VERSION} (${OS_TAG}/${ARCH_TAG})..."
echo "  from: ${URL}"
echo "  to:   ${INSTALL_DIR}/boxsh"

TMP="$(mktemp)"
SUMTMP="$(mktemp)"
trap 'rm -f "$TMP" "$SUMTMP"' EXIT

# Download
if ! curl -fSL -o "$TMP" "$URL"; then
    echo "Error: download failed. Check that the version and architecture are correct." >&2
    exit 1
fi
chmod +x "$TMP"

sha256_file() {
    target="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$target" | awk '{print $1}'
        return 0
    fi
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$target" | awk '{print $1}'
        return 0
    fi
    echo "Error: neither sha256sum nor shasum is available for checksum verification." >&2
    exit 1
}

verify_checksum() {
    if [ "${BOXSH_SKIP_CHECKSUM:-}" = "1" ]; then
        echo "Warning: skipping checksum verification because BOXSH_SKIP_CHECKSUM=1." >&2
        return 0
    fi

    if ! curl -fsSL -o "$SUMTMP" "$CHECKSUM_URL"; then
        echo "Error: checksum download failed: ${CHECKSUM_URL}" >&2
        echo "       Set BOXSH_SKIP_CHECKSUM=1 only for trusted local testing." >&2
        exit 1
    fi

    expected="$(sed -n 's/^\([0-9a-fA-F]\{64\}\).*/\1/p' "$SUMTMP" | head -1 | tr 'A-F' 'a-f')"
    actual="$(sha256_file "$TMP" | tr 'A-F' 'a-f')"
    if [ -z "$expected" ]; then
        echo "Error: checksum file does not contain a SHA-256 digest: ${CHECKSUM_URL}" >&2
        exit 1
    fi
    if [ "$actual" != "$expected" ]; then
        echo "Error: checksum mismatch for ${FILENAME}" >&2
        echo "       expected: ${expected}" >&2
        echo "       actual:   ${actual}" >&2
        exit 1
    fi
}

verify_checksum

resign_if_macos() {
    target="$1"
    if [ "$OS_TAG" != "darwin" ]; then
        return 0
    fi
    if ! command -v codesign >/dev/null 2>&1; then
        echo "Warning: codesign not found; installed binary may be rejected by macOS until re-signed manually." >&2
        return 0
    fi
    if ! codesign -f -s - "$target" >/dev/null 2>&1; then
        echo "Warning: failed to ad-hoc sign $target; macOS may refuse to launch it." >&2
        return 0
    fi
}

# Install
if [ -w "$INSTALL_DIR" ]; then
    mv "$TMP" "${INSTALL_DIR}/boxsh"
    resign_if_macos "${INSTALL_DIR}/boxsh"
else
    echo "  (need sudo to write to ${INSTALL_DIR})"
    sudo mv "$TMP" "${INSTALL_DIR}/boxsh"
    if [ "$OS_TAG" = "darwin" ]; then
        sudo codesign -f -s - "${INSTALL_DIR}/boxsh" >/dev/null 2>&1 || \
            echo "Warning: failed to ad-hoc sign ${INSTALL_DIR}/boxsh; macOS may refuse to launch it." >&2
    fi
fi

if ! "${INSTALL_DIR}/boxsh" --help >/dev/null; then
    echo "Error: installed boxsh failed to execute: ${INSTALL_DIR}/boxsh" >&2
    exit 1
fi

echo "Done! Run 'boxsh --help' to get started."
