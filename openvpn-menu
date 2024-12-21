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
SERVER_CONF="/etc/openvpn/server/server.conf"

# Get public IP of the server
get_public_ip() {
  curl -s http://checkip.amazonaws.com || echo "127.0.0.1"
}

# Install Easy-RSA and initialize PKI
setup_easy_rsa() {
  echo "Setting up Easy-RSA..."
  mkdir -p "$EASY_RSA_DIR"
  ln -s /usr/share/easy-rsa/* "$EASY_RSA_DIR" 2>/dev/null
  cd "$EASY_RSA_DIR"

  if [ ! -d "pki" ]; then
    ./easyrsa init-pki
    ./easyrsa --batch build-ca nopass
    ./easyrsa --batch gen-dh
    ./easyrsa --batch build-server-full vpnserver nopass
    openvpn --genkey --secret /etc/openvpn/server/ta.key
    echo "Easy-RSA setup complete."
  else
    echo "Easy-RSA already initialized."
  fi

  # Copy necessary files to server directory
  mkdir -p "$OPENVPN_CONFIG_DIR"
  cp "$EASY_RSA_DIR/pki/ca.crt" "$OPENVPN_CONFIG_DIR/"
  cp "$EASY_RSA_DIR/pki/issued/vpnserver.crt" "$OPENVPN_CONFIG_DIR/"
  cp "$EASY_RSA_DIR/pki/private/vpnserver.key" "$OPENVPN_CONFIG_DIR/"
  cp "$EASY_RSA_DIR/pki/dh.pem" "$OPENVPN_CONFIG_DIR/"
}

# Install OpenVPN and set up server configuration
install_openvpn() {
  echo "Installing OpenVPN and dependencies..."
  apt-get update -y
  apt-get install -y openvpn easy-rsa git

  # Configure server
  echo "Configuring OpenVPN server..."
  mkdir -p "$OPENVPN_CONFIG_DIR"
  cat <<EOF > "$SERVER_CONF"
port 1194
proto udp
dev tun
topology subnet
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-256-CBC
persist-key
persist-tun
user nobody
group nogroup
status /var/log/openvpn-status.log
log-append /var/log/openvpn.log
verb 3
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/vpnserver.crt
key /etc/openvpn/server/vpnserver.key
dh /etc/openvpn/server/dh.pem
tls-auth /etc/openvpn/server/ta.key 0
client-config-dir /etc/openvpn/server/ccd
EOF

  # Enable IP forwarding
  echo 1 > /proc/sys/net/ipv4/ip_forward
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

  # Set up Easy-RSA
  setup_easy_rsa

  # Start and enable OpenVPN service
  systemctl enable openvpn-server@server
  systemctl restart openvpn-server@server
}

# Add a new client configuration
add_client() {
  read -p "Enter the client name: " CLIENT_NAME
  CLIENT_CONFIG="$OPENVPN_CONFIG_DIR/ccd/$CLIENT_NAME"
  CLIENT_FILE="$CLIENT_FILES_DIR/$CLIENT_NAME.ovpn"

  # Get the server's public IP
  PUBLIC_IP=$(get_public_ip)

  # Generate client keys and certificates
  cd "$EASY_RSA_DIR"
  ./easyrsa build-client-full "$CLIENT_NAME" nopass --batch

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
  echo "Client configuration file created at: $CLIENT_FILE"
}

# Remove a client configuration
remove_client() {
  read -p "Enter the client name to remove: " CLIENT_NAME
  CLIENT_CONFIG="$OPENVPN_CONFIG_DIR/ccd/$CLIENT_NAME"
  CLIENT_FILE="$CLIENT_FILES_DIR/$CLIENT_NAME.ovpn"

  if [[ -f "$CLIENT_CONFIG" ]]; then
    rm "$CLIENT_CONFIG"
    echo "Client configuration removed: $CLIENT_CONFIG"
  else
    echo "No such client configuration found: $CLIENT_CONFIG"
  fi

  if [[ -f "$CLIENT_FILE" ]]; then
    rm "$CLIENT_FILE"
    echo "Client file removed: $CLIENT_FILE"
  else
    echo "No such client file found: $CLIENT_FILE"
  fi
}

# Menu
menu() {
  while true; do
    echo -e "\\n\\033[44m--- OpenVPN Management Menu ---\\033[0m"
    echo "1) Install OpenVPN"
    echo "2) Add a client"
    echo "3) Remove a client"
    echo "4) Exit"
    read -p "Choose an option: " OPTION

    case $OPTION in
      1)
        install_openvpn
        ;;
      2)
        add_client
        ;;
      3)
        remove_client
        ;;
      4)
        exit 0
        ;;
      *)
        echo "Invalid option. Please try again."
        ;;
    esac
  done
}

# Main script execution
menu
