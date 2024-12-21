#!/bin/bash

# Variables
REPO_URL="https://github.com/YorkshireNetUK/Vpn_With_Port_Forwarding.git"
MENU_REPO_URL="https://github.com/YorkshireNetUK/vpn-menu.git"
CLONE_DIR="/tmp/openvpn-setup"
MENU_CLONE_DIR="/tmp/vpn-menu"
FIREWALL_SCRIPT="firewall.sh"
INSTALL_DIR="/opt/openvpn"
SERVICE_FILE="/etc/systemd/system/openvpn-firewall.service"
PORTS_FILE="ports.txt"
LOCAL_PORTS_FILE="local_ports.txt"
BIN_DIR="/usr/local/bin"
MENU_SCRIPT="vpn-menu.sh"

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# Update and install required packages
echo "Updating system and installing Git..."
apt update && apt install -y git

# Install OpenVPN
echo "Downloading and running OpenVPN installation script..."
wget https://git.io/vpn -O openvpn-install.sh && bash openvpn-install.sh

# Clone the main repository
echo "Cloning repository from $REPO_URL..."
git clone "$REPO_URL" "$CLONE_DIR"

# Check if the repository contains the required files
if [ ! -f "$CLONE_DIR/$FIREWALL_SCRIPT" ]; then
  echo "Error: $FIREWALL_SCRIPT not found in the repository."
  exit 1
fi
if [ ! -f "$CLONE_DIR/$PORTS_FILE" ]; then
  echo "Error: $PORTS_FILE not found in the repository."
  exit 1
fi
if [ ! -f "$CLONE_DIR/$LOCAL_PORTS_FILE" ]; then
  echo "Error: $LOCAL_PORTS_FILE not found in the repository."
  exit 1
fi

# Create the installation directory if it doesn't exist
echo "Creating installation directory $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Move the firewall script and port files to the installation directory
echo "Moving $FIREWALL_SCRIPT, $PORTS_FILE, and $LOCAL_PORTS_FILE to $INSTALL_DIR..."
cp "$CLONE_DIR/$FIREWALL_SCRIPT" "$INSTALL_DIR/"
cp "$CLONE_DIR/$PORTS_FILE" "$INSTALL_DIR/"
cp "$CLONE_DIR/$LOCAL_PORTS_FILE" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/$FIREWALL_SCRIPT"

# Clone the vpn-menu repository
echo "Cloning VPN menu repository from $MENU_REPO_URL..."
git clone "$MENU_REPO_URL" "$MENU_CLONE_DIR"

# Check if the vpn-menu repository contains the menu script
if [ ! -f "$MENU_CLONE_DIR/$MENU_SCRIPT" ]; then
  echo "Error: $MENU_SCRIPT not found in the VPN menu repository."
  exit 1
fi

# Move the menu script to the bin directory
echo "Moving $MENU_SCRIPT to $BIN_DIR..."
cp "$MENU_CLONE_DIR/$MENU_SCRIPT" "$BIN_DIR/"
chmod +x "$BIN_DIR/$MENU_SCRIPT"

# Create the systemd service file
echo "Creating systemd service file..."
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Firewall setup for OpenVPN with port forwarding
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/$FIREWALL_SCRIPT
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd daemon
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable and start the service
echo "Enabling and starting the service..."
systemctl enable openvpn-firewall.service
systemctl start openvpn-firewall.service

# Check the service status
SERVICE_STATUS=$(systemctl is-active openvpn-firewall.service)
if [ "$SERVICE_STATUS" = "active" ]; then
  echo "Service started successfully!"
else
  echo "Error: Service failed to start. Check the logs using 'systemctl status openvpn-firewall.service'."
fi

# Cleanup
echo "Cleaning up temporary files..."
rm -rf "$CLONE_DIR"
rm -rf "$MENU_CLONE_DIR"

echo "Setup complete."
