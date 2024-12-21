#!/bin/bash

# Variables
REPO_URL="https://github.com/YorkshireNetUK/Vpn_With_Port_Forwarding.git"
CLONE_DIR="/tmp/openvpn-setup"
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
echo "Updating system and installing Git and sudo..."
apt update && apt install -y git sudo

# Install OpenVPN
function install_openvpn {
  echo "Installing OpenVPN..."

  # Detect OS
  if grep -qs "ubuntu" /etc/os-release; then
    os="ubuntu"
    os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
    group_name="nogroup"
  elif [[ -e /etc/debian_version ]]; then
    os="debian"
    os_version=$(grep -oE '[0-9]+' /etc/debian_version | head -1)
    group_name="nogroup"
  else
    echo "This installer is designed for Debian-based systems like Ubuntu and Debian."
    exit 1
  fi

  if [[ "$os" == "ubuntu" && "$os_version" -lt 2204 ]]; then
    echo "Ubuntu 22.04 or higher is required to use this installer."
    exit 1
  fi

  if [[ "$os" == "debian" && "$os_version" -lt 11 ]]; then
    echo "Debian 11 or higher is required to use this installer."
    exit 1
  fi

  # Install OpenVPN and required dependencies
  apt-get update
  apt-get install -y openvpn openssl ca-certificates iptables

  # Configure OpenVPN (example configuration for simplicity)
  mkdir -p /etc/openvpn/server/easy-rsa/
  cd /etc/openvpn/server/

  # Example: Generate necessary keys and certificates
  echo "Setting up EasyRSA for PKI management..."
  wget -qO- https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.8/EasyRSA-3.0.8.tgz | tar xz -C easy-rsa --strip-components 1
  cd easy-rsa
  ./easyrsa init-pki
  ./easyrsa build-ca nopass
  ./easyrsa gen-req server nopass
  ./easyrsa sign-req server server
  cp pki/private/server.key pki/issued/server.crt pki/ca.crt /etc/openvpn/server/

  # Example: Basic server.conf
  cat <<EOF > /etc/openvpn/server/server.conf
port 1194
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh none
topology subnet
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
keepalive 10 120
persist-key
persist-tun
status openvpn-status.log
log-append /var/log/openvpn.log
verb 3
EOF

  # Enable IP forwarding
  echo 1 > /proc/sys/net/ipv4/ip_forward
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

  # Start and enable OpenVPN service
  systemctl start openvpn-server@server
  systemctl enable openvpn-server@server

  echo "OpenVPN installation and setup complete."
}

install_openvpn

# Clone the repository
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
if [ ! -f "$CLONE_DIR/$MENU_SCRIPT" ]; then
  echo "Error: $MENU_SCRIPT not found in the repository."
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

# Move the VPN menu script to the bin directory
echo "Moving $MENU_SCRIPT to $BIN_DIR..."
cp "$CLONE_DIR/$MENU_SCRIPT" "$BIN_DIR/"
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

echo "Setup complete."
