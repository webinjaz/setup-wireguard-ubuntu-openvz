#!/bin/bash
######################################################################
# Script Name   : setup-wireguard.sh
# Description   : Full WireGuard VPN server setup for Ubuntu 24.04
# Author        : OpenAI ChatGPT
# Date          : 2025-10-16
# Purpose       : Automates installation, configuration, and client 
#                 setup of WireGuard, including firewall and QR codes.
######################################################################

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# -------------------------------#
#  Function: Print header
# -------------------------------#
echo "============================================"
echo " WireGuard VPN Setup Script for Ubuntu 24.04 "
echo "============================================"

# -------------------------------#
#  Detect public network interface
# -------------------------------#
echo "[INFO] Detecting public network interface..."
PUBLIC_IFACE=$(ip -o -4 route show to default | awk '{print $5}')
if [[ -z "$PUBLIC_IFACE" ]]; then
    echo "[ERROR] Could not detect public network interface!"
    exit 1
fi
echo "[INFO] Public interface detected: $PUBLIC_IFACE"

# -------------------------------#
# Fix broken packages
# -------------------------------#
echo "[INFO] Fixing broken packages..."
apt-get update -qq
apt-get install -y -qq --fix-broken tzdata python3 || true

# -------------------------------#
# Update and upgrade system
# -------------------------------#
echo "[INFO] Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# -------------------------------#
# Install dependencies
# -------------------------------#
echo "[INFO] Installing required packages..."
apt-get install -y -qq \
    wireguard-tools \
    qrencode \
    iptables-persistent \
    ufw \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    make \
    gcc \
    linux-headers-$(uname -r)

# -------------------------------#
# Install wireguard-go if missing
# -------------------------------#
if ! command -v wireguard-go &> /dev/null; then
    echo "[INFO] Installing wireguard-go..."
    WG_GO_VERSION="1.0.20230928" # Latest stable as of Oct 2025
    curl -Lo /usr/local/bin/wireguard-go "https://git.zx2c4.com/wireguard-go/snapshot/wireguard-go-${WG_GO_VERSION}.tar.gz"
    tar -xzf /usr/local/bin/wireguard-go -C /usr/local/bin/
    chmod +x /usr/local/bin/wireguard-go
fi

# -------------------------------#
# Enable IP forwarding
# -------------------------------#
echo "[INFO] Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf

# -------------------------------#
# Configure UFW firewall
# -------------------------------#
echo "[INFO] Configuring UFW firewall..."
ufw allow 22/tcp
ufw allow 51820/udp
ufw --force enable

# -------------------------------#
# Generate server and client keys
# -------------------------------#
echo "[INFO] Generating WireGuard keys..."
SERVER_PRIVKEY=$(wg genkey)
SERVER_PUBKEY=$(echo "$SERVER_PRIVKEY" | wg pubkey)

CLIENT1_PRIVKEY=$(wg genkey)
CLIENT1_PUBKEY=$(echo "$CLIENT1_PRIVKEY" | wg pubkey)

CLIENT2_PRIVKEY=$(wg genkey)
CLIENT2_PUBKEY=$(echo "$CLIENT2_PRIVKEY" | wg pubkey)

# -------------------------------#
# Define server IP and clients
# -------------------------------#
WG_NETWORK="10.66.66.0/24"
SERVER_IP="10.66.66.1"
CLIENT1_IP="10.66.66.2"
CLIENT2_IP="10.66.66.3"
PORT="51820"

mkdir -p /etc/wireguard/clients

# -------------------------------#
# Create server configuration
# -------------------------------#
echo "[INFO] Creating /etc/wireguard/wg0.conf..."
cat > /etc/wireguard/wg0.conf <<EOL
[Interface]
Address = ${SERVER_IP}/24
ListenPort = ${PORT}
PrivateKey = ${SERVER_PRIVKEY}
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${PUBLIC_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${PUBLIC_IFACE} -j MASQUERADE
SaveConfig = true

[Peer]
PublicKey = ${CLIENT1_PUBKEY}
AllowedIPs = ${CLIENT1_IP}/32

[Peer]
PublicKey = ${CLIENT2_PUBKEY}
AllowedIPs = ${CLIENT2_IP}/32
EOL

chmod 600 /etc/wireguard/wg0.conf

# -------------------------------#
# Create client configurations
# -------------------------------#
echo "[INFO] Creating client configuration files..."

for i in 1 2; do
  CLIENT_PRIVKEY_VAR="CLIENT${i}_PRIVKEY"
  CLIENT_PUBKEY_VAR="CLIENT${i}_PUBKEY"
  CLIENT_IP_VAR="CLIENT${i}_IP"
  
  CLIENT_CONF="/etc/wireguard/clients/client${i}.conf"
  
  cat > "$CLIENT_CONF" <<EOL
[Interface]
PrivateKey = ${!CLIENT_PRIVKEY_VAR}
Address = ${!CLIENT_IP_VAR}/24
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUBKEY}
Endpoint = $(curl -s ifconfig.me):${PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOL

  chmod 600 "$CLIENT_CONF"
  
  # Generate QR code for mobile apps
  echo "[INFO] QR code for client${i}:"
  qrencode -t ansiutf8 < "$CLIENT_CONF"
done

# -------------------------------#
# Enable and start WireGuard service
# -------------------------------#
echo "[INFO] Enabling wg-quick@wg0.service..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# -------------------------------#
# Display status
# -------------------------------#
echo "[INFO] WireGuard installation and configuration complete!"
echo "Server public key: $SERVER_PUBKEY"
echo "Clients configuration files: /etc/wireguard/clients/"
echo
echo "Usage:"
echo "  Start VPN: systemctl start wg-quick@wg0"
echo "  Stop VPN : systemctl stop wg-quick@wg0"
echo "  Status   : systemctl status wg-quick@wg0"
echo "  View client configs: cat /etc/wireguard/clients/client1.conf"
echo "  Scan QR codes for mobile clients: qrencode -t ansiutf8 < /etc/wireguard/clients/client1.conf"
