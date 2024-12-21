#!/bin/bash

# Variables
REPO_URL="https://github.com/YorkshireNetUK/Vpn_With_Port_Forwarding.git"
INSTALL_DIR="/opt/firewall"
SERVICE_NAME="firewall.service"
BIN_LINK="/usr/bin/vpn-menu"

# Update and install git if not installed
echo "Installing git if not already installed..."
sudo apt-get update -y
sudo apt-get install -y git

# Clone repository
echo "Cloning repository..."
sudo git clone $REPO_URL $INSTALL_DIR

# Check if cloning was successful
if [[ $? -ne 0 ]]; then
    echo "Failed to clone repository. Exiting."
    exit 1
fi

# Make files executable
echo "Making scripts executable..."
sudo chmod +x $INSTALL_DIR/firewall.sh
sudo chmod +x $INSTALL_DIR/vpn-menu

# Create systemd service file
echo "Creating systemd service for firewall.sh..."
cat << EOF | sudo tee /etc/systemd/system/$SERVICE_NAME > /dev/null
[Unit]
Description=Firewall Service
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/firewall.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable, and start the service
echo "Enabling and starting the firewall service..."
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl start $SERVICE_NAME

# Check service status
sudo systemctl status $SERVICE_NAME --no-pager

# Create symlink for vpn-menu
echo "Creating symbolic link for vpn-menu in /usr/bin..."
if [[ -f $INSTALL_DIR/vpn-menu ]]; then
    sudo ln -sf $INSTALL_DIR/vpn-menu $BIN_LINK
else
    echo "vpn-menu not found in $INSTALL_DIR. Skipping symbolic link creation."
fi

echo "Installation and setup complete!"
