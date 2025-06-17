#!/bin/bash
set -e

# Get version (e.g. go1.22.3)
VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n1)
TARBALL="go${VERSION}.linux-amd64.tar.gz"
URL="https://dl.google.com/go/${TARBALL}"

echo "[*] Fetching Go version ${VERSION}..."
curl -LO "$URL"

echo "[*] Removing old Go installation..."
 rm -rf /usr/local/go

echo "[*] Extracting to /usr/local ..."
 tar -C /usr/local -xzf "$TARBALL"

echo "[*] Cleaning up..."
rm -f "$TARBALL"

# Add to PATH if missing
PROFILE="$HOME/.bashrc"
if [ -n "$ZSH_VERSION" ]; then PROFILE="$HOME/.zshrc"; fi
if ! grep -q '/usr/local/go/bin' "$PROFILE"; then
  echo 'export PATH=$PATH:/usr/local/go/bin' >> "$PROFILE"
  echo "[*] PATH updated in $PROFILE"
fi

echo "[*] Sourcing $PROFILE..."
source "$PROFILE" || true

echo "[*] Installed:" $(go version)
