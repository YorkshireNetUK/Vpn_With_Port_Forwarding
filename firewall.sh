#!/bin/bash

# Firewall setup for OpenVPN with port forwarding
# ports.txt format: IP=<IP_ADDRESS> UDP=<UDP_PORTS> TCP=<TCP_PORTS>
# local_ports.txt format: TCP=<TCP_PORTS> UDP=<UDP_PORTS>

PORTS_FILE="/opt/openvpn/ports.txt"
LOCAL_PORTS_FILE="/opt/openvpn/local_ports.txt"

# Flush existing rules
iptables -F
iptables -t nat -F
iptables -X

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback interface
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established and related connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow OpenVPN port (typically 1194)
iptables -A INPUT -p udp --dport 1194 -j ACCEPT
iptables -A INPUT -p tcp --dport 1194 -j ACCEPT

# Load port forwarding rules from ports.txt
if [[ -f $PORTS_FILE ]]; then
  echo "Loading port forwarding rules from $PORTS_FILE..."
  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

    # Extract fields from the line
    eval $line

    # Allow TCP ports for the client
    if [[ ! -z "$TCP" ]]; then
      IFS=',' read -r -a TCP_PORT_ARRAY <<< "$TCP"
      for PORT in "${TCP_PORT_ARRAY[@]}"; do
        iptables -t nat -A PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $IP
        iptables -A FORWARD -p tcp -d $IP --dport $PORT -j ACCEPT
      done
    fi

    # Allow UDP ports for the client
    if [[ ! -z "$UDP" ]]; then
      IFS=',' read -r -a UDP_PORT_ARRAY <<< "$UDP"
      for PORT in "${UDP_PORT_ARRAY[@]}"; do
        iptables -t nat -A PREROUTING -p udp --dport $PORT -j DNAT --to-destination $IP
        iptables -A FORWARD -p udp -d $IP --dport $PORT -j ACCEPT
      done
    fi
  done < "$PORTS_FILE"
else
  echo "$PORTS_FILE not found. No port forwarding rules applied."
fi

# Load local port rules from local_ports.txt
if [[ -f $LOCAL_PORTS_FILE ]]; then
  echo "Loading local ports from $LOCAL_PORTS_FILE..."
  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

    # Parse TCP and UDP ports
    eval $line

    # Allow TCP ports for the local server
    if [[ ! -z "$TCP" ]]; then
      IFS=',' read -r -a TCP_PORT_ARRAY <<< "$TCP"
      for PORT in "${TCP_PORT_ARRAY[@]}"; do
        iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT
      done
    fi

    # Allow UDP ports for the local server
    if [[ ! -z "$UDP" ]]; then
      IFS=',' read -r -a UDP_PORT_ARRAY <<< "$UDP"
      for PORT in "${UDP_PORT_ARRAY[@]}"; do
        iptables -A INPUT -p udp --dport "$PORT" -j ACCEPT
      done
    fi
  done < "$LOCAL_PORTS_FILE"
else
  echo "$LOCAL_PORTS_FILE not found. No local ports added."
fi

# Allow inter-client communication
iptables -A FORWARD -i tun0 -o tun0 -j ACCEPT

# Save the rules
iptables-save > /etc/iptables/rules.v4

echo "Firewall rules applied successfully."
