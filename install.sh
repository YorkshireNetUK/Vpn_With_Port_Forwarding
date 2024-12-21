#!/bin/bash

# OpenVPN installer and management script

# Constants
PORTS_FILE="/opt/openvpn/ports.txt"
LOCAL_PORTS_FILE="/opt/openvpn/local_ports.txt"
OPENVPN_CONFIG_DIR="/etc/openvpn/server"
CLIENT_FILES_DIR="/opt/openvpn/client"
FIREWALL_SCRIPT="/opt/openvpn/firewall.sh"
FIREWALL_SERVICE="firewall"
EASY_RSA_DIR="/etc/openvpn/easy-rsa"

# Get public IP of the server
get_public_ip() {
  curl -s http://checkip.amazonaws.com || echo "127.0.0.1"
}

# Find the next available IP for a new client
get_next_client_ip() {
  BASE_IP="10.8.0"
  for i in {2..254}; do
    IP="$BASE_IP.$i"
    if ! grep -q "$IP" "$PORTS_FILE"; then
      echo "$IP"
      return
    fi
  done
  echo "No available IP addresses left." >&2
  exit 1
}

# Install Easy-RSA and initialize PKI
setup_easy_rsa() {
  echo "Setting up Easy-RSA..."
  mkdir -p "$EASY_RSA_DIR"
  ln -s /usr/share/easy-rsa/* "$EASY_RSA_DIR" 2>/dev/null
  cd "$EASY_RSA_DIR"
  if [ ! -d "pki" ]; then
    ./easyrsa init-pki
    ./easyrsa build-ca nopass
    ./easyrsa gen-dh
    ./easyrsa gen-crl
    openvpn --genkey --secret /etc/openvpn/server/ta.key
    ./easyrsa build-server-full server nopass
    echo "Easy-RSA setup complete."
  else
    echo "Easy-RSA already initialized."
  fi
}

# Install OpenVPN if not already installed
install_openvpn() {
  echo "Checking for OpenVPN installation..."
  if ! command -v openvpn &>/dev/null; then
    echo "Installing OpenVPN and Git..."
    apt-get update
    apt-get install -y openvpn easy-rsa git
    echo "OpenVPN and Git installed successfully."

    # Clone repository and set up the firewall.sh script and related files
    echo "Cloning repository and setting up firewall.sh..."
    mkdir -p /opt/openvpn
    git clone https://github.com/YorkshireNetUK/Vpn_With_Port_Forwarding.git /opt/openvpn
    chmod +x "$FIREWALL_SCRIPT"

    # Install openvpn-menu from the repository
    echo "Setting up openvpn-menu..."
    cp /opt/openvpn/openvpn-menu /usr/local/bin/openvpn-menu
    chmod +x /usr/local/bin/openvpn-menu

    # Create systemd service for firewall.sh
    echo "Creating systemd service for firewall.sh..."
    cat <<EOF > /etc/systemd/system/$FIREWALL_SERVICE.service
[Unit]
Description=Firewall script for OpenVPN
After=network.target

[Service]
ExecStart=$FIREWALL_SCRIPT
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable $FIREWALL_SERVICE
    systemctl start $FIREWALL_SERVICE

    echo "firewall.sh service set up and started."
  else
    echo "OpenVPN is already installed."
  fi

  # Create directory for client files
  mkdir -p "$CLIENT_FILES_DIR"
  mkdir -p "$OPENVPN_CONFIG_DIR/ccd"

  # Set up Easy-RSA
  setup_easy_rsa
}

# Add a new client configuration
add_client() {
  read -p "Enter the client name: " CLIENT_NAME
  CLIENT_CONFIG="$OPENVPN_CONFIG_DIR/ccd/$CLIENT_NAME"
  CLIENT_FILE="$CLIENT_FILES_DIR/$CLIENT_NAME.ovpn"

  # Get the next available IP for the client
  CLIENT_IP=$(get_next_client_ip)
  echo "ifconfig-push $CLIENT_IP 255.255.255.0" > "$CLIENT_CONFIG"
  echo "$CLIENT_NAME configuration created with IP $CLIENT_IP."

  echo "Enter forwarding ports for this client."
  read -p "TCP ports (comma-separated): " TCP_PORTS
  read -p "UDP ports (comma-separated): " UDP_PORTS

  echo "IP=$CLIENT_IP TCP=$TCP_PORTS UDP=$UDP_PORTS" >> "$PORTS_FILE"
  echo "Client $CLIENT_NAME added to $PORTS_FILE."

  # Get server public IP
  PUBLIC_IP=$(get_public_ip)

  # Generate client keys and certificates using Easy-RSA
  cd "$EASY_RSA_DIR"
  ./easyrsa build-client-full "$CLIENT_NAME" nopass

  CLIENT_CERT=$(cat "$EASY_RSA_DIR/pki/issued/$CLIENT_NAME.crt")
  CLIENT_KEY=$(cat "$EASY_RSA_DIR/pki/private/$CLIENT_NAME.key")
  CA_CERT=$(cat "$EASY_RSA_DIR/pki/ca.crt")
  TA_KEY=$(cat "$OPENVPN_CONFIG_DIR/ta.key")

  # Generate client .ovpn file
  echo "Generating .ovpn file for $CLIENT_NAME..."
  cat <<EOF > "$CLIENT_FILE"
client
dev tun
proto udp
remote $PUBLIC_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
key-direction 1
<ca>
$CA_CERT
</ca>
<cert>
$CLIENT_CERT
</cert>
<key>
$CLIENT_KEY
</key>
<tls-auth>
$TA_KEY
</tls-auth>
EOF
  echo "$CLIENT_FILE created."
}

# Remove a client
remove_client() {
  read -p "Enter the client name to remove: " CLIENT_NAME
  CLIENT_CONFIG="$OPENVPN_CONFIG_DIR/ccd/$CLIENT_NAME"
  CLIENT_FILE="$CLIENT_FILES_DIR/$CLIENT_NAME.ovpn"

  if [[ -f "$CLIENT_CONFIG" ]]; then
    rm "$CLIENT_CONFIG"
    sed -i "/$CLIENT_NAME/d" "$PORTS_FILE"
    echo "Client $CLIENT_NAME removed from $CLIENT_CONFIG."
  else
    echo "Client configuration not found."
  fi

  if [[ -f "$CLIENT_FILE" ]]; then
    rm "$CLIENT_FILE"
    echo "Client file $CLIENT_FILE removed."
  else
    echo "Client file not found."
  fi
}

# Add ports to ports.txt
edit_ports_txt() {
  echo "Editing $PORTS_FILE..."
  read -p "Enter the IP: " IP
  read -p "TCP ports (comma-separated): " TCP_PORTS
  read -p "UDP ports (comma-separated): " UDP_PORTS

  echo "IP=$IP TCP=$TCP_PORTS UDP=$UDP_PORTS" >> "$PORTS_FILE"
  echo "Ports added to $PORTS_FILE."
}

# Add ports to local_ports.txt
edit_local_ports_txt() {
  echo "Editing $LOCAL_PORTS_FILE..."
  read -p "TCP ports (comma-separated): " TCP_PORTS
  read -p "UDP ports (comma-separated): " UDP_PORTS

  echo "TCP=$TCP_PORTS UDP=$UDP_PORTS" >> "$LOCAL_PORTS_FILE"
  echo "Ports added to $LOCAL_PORTS_FILE."
}

# Display connected clients
show_connected_clients() {
  echo "Fetching connected clients..."
  status_file="/etc/openvpn/openvpn-status.log"

  if [[ -f "$status_file" ]]; then
    echo -e "\\n--- Connected Clients ---"
    grep "10.8." "$status_file" | awk '{print "Client IP: " $1 ", Bytes Received: " $3 ", Bytes Sent: " $4}'
  else
    echo "Status file not found. Ensure OpenVPN status logging is enabled."
  fi
}

# Restart firewall.sh service
restart_firewall() {
  echo "Restarting firewall.sh service..."
  systemctl restart "$FIREWALL_SERVICE"
  echo "firewall.sh service restarted."
}

# Menu
menu() {
  while true; do
    echo -e "\\n\\033[44m--- OpenVPN Management Menu ---\\033[0m"
    echo "1) Add a client"
    echo "2) Remove a client"
    echo "3) Edit $PORTS_FILE"
    echo "4) Edit $LOCAL_PORTS_FILE"
    echo "5) Restart firewall"
    echo "6) Show connected clients"
    echo "7) Exit"
    read -p "Choose an option: " OPTION

    case $OPTION in
      1)
        add_client
        ;;
      2)
        remove_client
        ;;
      3)
        edit_ports_txt
        ;;
      4)
        edit_local_ports_txt
        ;;
      5)
        restart_firewall
        ;;
      6)
        show_connected clients
        ;;
      7)
        exit 0
        ;;
      *)
        echo "Invalid option. Please try again."
        ;;
    esac
  done
}

# Main script execution
install_openvpn
menu
