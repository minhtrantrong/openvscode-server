#!/usr/bin/env bash
#
# Build & Setup script for OpenVSCode Server systemd service
#
# This script compiles the project from source, then configures it as a
# systemd service. Run this from the project root after cloning the repo.
#
# Prerequisites:
#   - Node.js (LTS) and npm
#   - build-essential / gcc (for native modules)
#

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

OPENVSCODE_USER="devx"
OPENVSCODE_GROUP="devx"
TOKEN_DIR="/etc/openvscode-server"
TOKEN_FILE="${TOKEN_DIR}/connection-token"
SERVICE_FILE="/etc/systemd/system/openvscode-server.service"
INSTALL_DIR="/opt/vscode-server"
DATA_DIR="${INSTALL_DIR}/data"

# Determine the project root (directory where this script lives, then go up)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "============================================"
echo " OpenVSCode Server — Build & Setup"
echo "============================================"
echo "Project root : ${PROJECT_ROOT}"
echo "Install dir  : ${INSTALL_DIR}"
echo "Data dir     : ${DATA_DIR}"
echo "Token file   : ${TOKEN_FILE}"
echo "Service file : ${SERVICE_FILE}"
echo ""

# ─── Step 1: Verify we are in the project root ───────────────────────────────

if [ ! -f "${PROJECT_ROOT}/package.json" ]; then
    echo "[FAIL] Cannot find 'package.json' — make sure you cloned the repository."
    exit 1
fi

# ─── Step 2: Install npm dependencies ────────────────────────────────────────

echo "[...] Installing npm dependencies..."
cd "${PROJECT_ROOT}"
npm ci --omit=optional 2>&1 | tail -5
echo "[OK] npm dependencies installed."
echo ""

# ─── Step 3: Compile the project ─────────────────────────────────────────────

echo "[...] Compiling TypeScript sources (npm run compile)..."
npm run compile 2>&1 | tail -10
echo "[OK] Compilation finished."
echo ""

# ─── Step 4: Download built-in extensions ────────────────────────────────────

echo "[...] Downloading built-in extensions..."
npm run download-builtin-extensions 2>&1 | tail -5
echo "[OK] Built-in extensions downloaded."
echo ""

# ─── Step 5: Create the bin/openvscode-server entry point ────────────────────
#
# In a production release tarball the entry point is baked during packaging.
# Since we compile from source, we create it manually.

echo "[...] Creating bin/openvscode-server entry point..."
mkdir -p "${PROJECT_ROOT}/bin"

cat > "${PROJECT_ROOT}/bin/openvscode-server" << 'BINEOF'
#!/usr/bin/env sh
#
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.
#
# OpenVSCode Server entry point (built from source).
#

case "$1" in
	--inspect*) INSPECT="$1"; shift;;
esac

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"

# Set rpath before changing the interpreter path
# Refs https://github.com/NixOS/patchelf/issues/524
if [ -n "$VSCODE_SERVER_CUSTOM_GLIBC_LINKER" ] && [ -n "$VSCODE_SERVER_CUSTOM_GLIBC_PATH" ] && [ -n "$VSCODE_SERVER_PATCHELF_PATH" ]; then
	echo "Patching glibc from $VSCODE_SERVER_CUSTOM_GLIBC_PATH with $VSCODE_SERVER_PATCHELF_PATH..."
	"$VSCODE_SERVER_PATCHELF_PATH" --set-rpath "$VSCODE_SERVER_CUSTOM_GLIBC_PATH" "$ROOT/node"
	echo "Patching linker from $VSCODE_SERVER_CUSTOM_GLIBC_LINKER with $VSCODE_SERVER_PATCHELF_PATH..."
	"$VSCODE_SERVER_PATCHELF_PATH" --set-interpreter "$VSCODE_SERVER_CUSTOM_GLIBC_LINKER" "$ROOT/node"
	echo "Patching complete."
fi

"$ROOT/node" ${INSPECT:-} "$ROOT/out/server-main.js" "$@"
BINEOF

chmod +x "${PROJECT_ROOT}/bin/openvscode-server"
echo "[OK] bin/openvscode-server created."
echo ""

# ─── Step 6: Create the devx system user (if not already present) ────────────

if id "${OPENVSCODE_USER}" &>/dev/null; then
    echo "[OK] User '${OPENVSCODE_USER}' already exists."
else
    echo "[...] Creating user '${OPENVSCODE_USER}'..."
    sudo useradd --system --no-create-home --shell /bin/bash "${OPENVSCODE_USER}"
    echo "[OK] User '${OPENVSCODE_USER}' created."
fi
echo ""

# ─── Step 7: Copy the compiled project to the install directory ──────────────

if [ -d "${INSTALL_DIR}" ]; then
    echo "[OK] Installation directory '${INSTALL_DIR}' already exists — skipping copy."
    echo "     Remove it first if you want a fresh copy:"
    echo "       sudo rm -rf ${INSTALL_DIR}"
else
    echo "[...] Copying project to '${INSTALL_DIR}'..."
    sudo mkdir -p "$(dirname "${INSTALL_DIR}")"
    sudo cp -a "${PROJECT_ROOT}" "${INSTALL_DIR}"
    sudo chown -R "${OPENVSCODE_USER}:${OPENVSCODE_GROUP}" "${INSTALL_DIR}"
    echo "[OK] Project copied to '${INSTALL_DIR}'."
fi
echo ""

# ─── Step 8: Create the server data directory ────────────────────────────────

if [ -d "${DATA_DIR}" ]; then
    echo "[OK] Data directory '${DATA_DIR}' already exists."
else
    echo "[...] Creating data directory '${DATA_DIR}'..."
    sudo mkdir -p "${DATA_DIR}"
    sudo chown -R "${OPENVSCODE_USER}:${OPENVSCODE_GROUP}" "${DATA_DIR}"
    echo "[OK] Data directory created."
fi
echo ""

# ─── Step 9: Generate a secure random connection token ───────────────────────

echo "[...] Generating connection token..."
sudo mkdir -p "${TOKEN_DIR}"
TOKEN="$(openssl rand -hex 48)"
echo -n "${TOKEN}" | sudo tee "${TOKEN_FILE}" > /dev/null
sudo chmod 600 "${TOKEN_FILE}"
sudo chown "${OPENVSCODE_USER}:${OPENVSCODE_GROUP}" "${TOKEN_FILE}"
echo "[OK] Connection token written to '${TOKEN_FILE}' (mode 600)."
echo ""
echo "    Your connection token is: ${TOKEN}"
echo "    Save this securely — you will need it to access the IDE."
echo ""

# ─── Step 10: Install the systemd service file ──────────────────────────────

SERVICE_SOURCE="${INSTALL_DIR}/scripts/openvscode-server.service"
if [ ! -f "${SERVICE_SOURCE}" ]; then
    echo "[FAIL] Service file not found at '${SERVICE_SOURCE}'."
    echo "       Make sure 'scripts/openvscode-server.service' exists in the project."
    exit 1
fi

echo "[...] Installing service file to '${SERVICE_FILE}'..."
sudo cp "${SERVICE_SOURCE}" "${SERVICE_FILE}"
sudo chmod 644 "${SERVICE_FILE}"
echo "[OK] Service file installed."
echo ""

# ─── Step 11: Reload systemd and enable the service ─────────────────────────

echo "[...] Reloading systemd daemon..."
sudo systemctl daemon-reload
echo "[OK] systemd reloaded."

echo "[...] Enabling service to start on boot..."
sudo systemctl enable openvscode-server.service
echo "[OK] Service enabled."
echo ""

# ─── Done ────────────────────────────────────────────────────────────────────

echo "============================================"
echo " Build & Setup complete!"
echo "============================================"
echo ""
echo "Start the service now:"
echo "  sudo systemctl start openvscode-server"
echo ""
echo "Check status:"
echo "  sudo systemctl status openvscode-server"
echo ""
echo "View logs:"
echo "  sudo journalctl -u openvscode-server -f"
echo ""
echo "Retrieve the connection token later:"
echo "  sudo cat ${TOKEN_FILE}"
echo ""
