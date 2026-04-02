#!/bin/bash
# install.sh - Install sdd-harness to ~/.local/bin
# Usage: bash install.sh
#    or: curl -fsSL <raw-url>/install.sh | bash

set -euo pipefail

INSTALL_DIR="${SDD_INSTALL_DIR:-$HOME/.local/bin}"
REPO_URL="https://github.com/gsy44355/sdd-harness"

# Determine source directory
if [ -f "$(dirname "$0")/sdd-harness" ]; then
    # Running from cloned repo
    SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
else
    # Running from curl pipe - clone to temp
    SRC_DIR=$(mktemp -d)
    echo "Cloning sdd-harness..."
    git clone --depth 1 "$REPO_URL" "$SRC_DIR" 2>/dev/null || {
        echo "Error: Could not clone $REPO_URL"
        echo "Please clone the repo manually and run install.sh from the repo directory."
        rm -rf "$SRC_DIR"
        exit 1
    }
    trap "rm -rf '$SRC_DIR'" EXIT
fi

# Verify source files exist
for f in sdd-harness sdd-loop.sh; do
    if [ ! -f "$SRC_DIR/$f" ]; then
        echo "Error: $f not found in $SRC_DIR"
        exit 1
    fi
done

if [ ! -d "$SRC_DIR/templates" ]; then
    echo "Error: templates/ directory not found in $SRC_DIR"
    exit 1
fi

# Create install directory
mkdir -p "$INSTALL_DIR"

# Create a wrapper that knows where the repo lives
# sdd-harness needs SCRIPT_DIR to find templates/ and sdd-loop.sh
# So we create a symlink to the actual repo
SDD_HOME="${SDD_HOME:-$HOME/.sdd-harness}"
mkdir -p "$SDD_HOME"

# Copy all necessary files to SDD_HOME
cp "$SRC_DIR/sdd-harness" "$SDD_HOME/"
cp "$SRC_DIR/sdd-loop.sh" "$SDD_HOME/"
cp -r "$SRC_DIR/templates" "$SDD_HOME/"
chmod +x "$SDD_HOME/sdd-harness"
chmod +x "$SDD_HOME/sdd-loop.sh"

# Create symlink in PATH
ln -sf "$SDD_HOME/sdd-harness" "$INSTALL_DIR/sdd-harness"

echo ""
echo "sdd-harness installed successfully!"
echo ""
echo "  Binary:    $INSTALL_DIR/sdd-harness"
echo "  Home:      $SDD_HOME/"
echo ""

# Check if INSTALL_DIR is in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    echo "NOTE: $INSTALL_DIR is not in your PATH."
    echo "Add it with:"
    echo ""
    echo "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.zshrc"
    echo "  source ~/.zshrc"
    echo ""
fi

echo "Usage:"
echo "  cd your-project/"
echo "  sdd-harness init"
echo "  ./sdd-loop.sh \"Build a REST API for...\""
