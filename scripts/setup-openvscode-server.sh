#!/usr/bin/env bash
#
# Setup script for OpenVSCode Server systemd service
# This script creates the necessary directories, user, and connection token.
#

set -euo pipefail

OPENVSCODE_USER="devx"
OPENVSCODE_GROUP="devx"
TOKEN_DIR="/etc/openvscode-server"
TOKEN_FILE="${TOKEN_DIR}/connection-token"
SERVICE_FILE="/etc/systemd/system/openvscode-server.service"
INSTALL_DIR="/opt/vscode-server"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== OpenVSCode Server Systemd Service Setup ==="

# 1. Create the devx system user (if not already present)
if id "${OPENVSCODE_USER}" &>/dev/null; then
    echo "[OK] User '${OPENVSCODE_USER}' already exists."
else
    echo "[...] Creating user '${OPENVSCODE_USER}'..."
    sudo useradd --system --no-create-home --shell /bin/bash "${OPENVSCODE_USER}"
    echo "[OK] User '${OPENVSCODE_USER}' created."
fi

# 2. Move installation to /opt/vscode-server if not already there
if [ -d "${INSTALL_DIR}" ]; then
    echo "[OK] Installation directory '${INSTALL_DIR}' already exists — skipping move."
else
    echo "[...] Moving installation to '${INSTALL_DIR}'..."
    sudo mkdir -p "$(dirname "${INSTALL_DIR}")"
    sudo cp -a "${SCRIPT_DIR}" "${INSTALL_DIR}"
    sudo chown -R "${OPENVSCODE_USER}:${OPENVSCODE_GROUP}" "${INSTALL_DIR}"
    echo "[OK] Installation moved to '${INSTALL_DIR}'."
fi

# 3. Create the server data directory with proper ownership
DATA_DIR="/opt/vscode-server/data"
if [ -d "${DATA_DIR}" ]; then
    echo "[OK] Data directory '${DATA_DIR}' already exists."
else
    echo "[...] Creating data directory '${DATA_DIR}'..."
    sudo mkdir -p "${DATA_DIR}"
    sudo chown -R "${OPENVSCODE_USER}:${OPENVSCODE_GROUP}" "${DATA_DIR}"
    echo "[OK] Data directory created."
fi

# 4. Create the token directory with restricted permissions

# 5. Generate a secure random connection token
echo "[...] Generating connection token..."
TOKEN="$(openssl rand -hex 48)"
echo -n "${TOKEN}" | sudo tee "${TOKEN_FILE}" > /dev/null
sudo chmod 600 "${TOKEN_FILE}"
sudo chown "${OPENVSCODE_USER}:${OPENVSCODE_GROUP}" "${TOKEN_FILE}"
echo "[OK] Connection token written to '${TOKEN_FILE}' (mode 600)."
echo ""
echo "    Your connection token is: ${TOKEN}"
echo "    Save this securely — you will need it to access the IDE."
echo ""

# 6. Install the systemd service file (always overwrites)
echo "[...] Installing service file to '${SERVICE_FILE}'..."
sudo cp "${INSTALL_DIR}/openvscode-server.service" "${SERVICE_FILE}"
sudo chmod 644 "${SERVICE_FILE}"
echo "[OK] Service file installed."

# 7. Reload systemd and enable the service
echo "[...] Reloading systemd daemon..."
sudo systemctl daemon-reload
echo "[OK] systemd reloaded."

echo "[...] Enabling service to start on boot..."
sudo systemctl enable openvscode-server.service
echo "[OK] Service enabled."

echo ""
echo "=== Setup complete! ==="
echo ""
echo "To start the service now:"
echo "  sudo systemctl start openvscode-server"
echo ""
echo "To check the status:"
echo "  sudo systemctl status openvscode-server"
echo ""
echo "To view logs:"
echo "  sudo journalctl -u openvscode-server -f"
echo ""
echo "To retrieve the connection token later:"
echo "  sudo cat /etc/openvscode-server/connection-token"
