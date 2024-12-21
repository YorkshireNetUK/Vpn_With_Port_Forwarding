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

# Install OpenVPN and set up server configuration
install_openvpn() {
  echo "Installing OpenVPN and dependencies..."
  apt-get update
  apt-get install -y openvpn easy-rsa git

  # Configure server
  echo "Configuring OpenVPN server..."
  mkdir -p "$OPENVPN_CONFIG_DIR"
  cat <<EOF > "$SERVER_CONF"
port 1194
proto udp
dev tun
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
cipher AES-256-CBC
auth SHA256
persist-key
persist-tun
user nobody
group nogroup
status /var/log/openvpn-status.log
log-append /var/log/openvpn.log
verb 3
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
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
  systemctl start openvpn-server@server
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

# Restart OpenVPN service
restart_openvpn() {
  systemctl restart openvpn-server@server
}

# Menu
menu() {
  while true; do
    echo -e "\\n--- OpenVPN Management Menu ---"
    echo "1) Add a client"
    echo "2) Restart OpenVPN"
    echo "3) Exit"
    read -p "Choose an option: " OPTION

    case $OPTION in
      1)
        add_client
        ;;
      2)
        restart_openvpn
        ;;
      3)
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
