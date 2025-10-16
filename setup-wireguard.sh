#!/bin/bash
# ====================================================
# WireGuard VPN Auto-Setup Script for Ubuntu 24.04+
# ====================================================
#
# This script will:
#  1. Update your system packages.
#  2. Install WireGuard and required tools (wireguard-tools, qrencode, ufw).
#  3. Configure UFW firewall (allow SSH + WireGuard port).
#  4. Enable IP forwarding.
#  5. Generate WireGuard server keys and configuration.
#  6. Generate multiple client configs with QR codes for mobile apps.
#  7. Enable and start WireGuard as a systemd service.
#
# Requirements:
#  - Ubuntu 24.04+ 64-bit
#  - At least 256 MB RAM
#  - Root privileges (run with sudo)
#
# Usage:
#  1. Download the script: 
#       curl -O https://example.com/setup-wireguard.sh
#  2. Make it executable:
#       chmod +x setup-wireguard.sh
#  3. Run as root:
#       sudo ./setup-wireguard.sh
#
# Notes:
#  - Existing WireGuard configurations may be overwritten.
#  - Client configs will be saved under /root/clientN.conf.
#  - QR codes will be displayed in the terminal for mobile setup.
#  - Use 'sudo wg show' to verify connection status.
#
# Author: ChatGPT
# Last Updated: 2025-10-16
# ====================================================

set -e

LOG_FILE="/var/log/wireguard-setup.log"
WG_CONF_DIR="/etc/wireguard"
WG_INTERFACE="wg0"
SERVER_PORT=51820
SERVER_SUBNET="10.66.66.0/24"
SERVER_IP="10.66.66.1"
NET_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
CLIENT_COUNT=2  # Change this number to add more clients

timestamp() { date +"[%Y-%m-%d %H:%M:%S]"; }
log() { echo "$(timestamp) $1"; echo "$(timestamp) $1" >> "$LOG_FILE"; }

log "=== Starting WireGuard VPN setup ==="

# Step 0: Fix broken packages
log "Checking and fixing broken packages..."
apt --fix-broken install -y || log "No broken packages or fixed successfully."

# Step 1: Update system
log "Updating system packages..."
apt update -y && apt upgrade -y

# Step 2: Install required packages
log "Installing dependencies..."
apt install -y wireguard wireguard-tools qrencode ufw resolvconf curl

# Step 3: Configure firewall
log "Configuring UFW..."
ufw allow 22/tcp
ufw allow ${SERVER_PORT}/udp
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

# Step 4: Enable IP forwarding
log "Enabling IP forwarding..."
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p

# Step 5: Generate server keys
log "Generating server keys..."
mkdir -p ${WG_CONF_DIR}
SERVER_PRIVATE_KEY=$(wg genkey)
SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)

# Step 6: Create WireGuard server config
log "Creating server configuration..."
cat > ${WG_CONF_DIR}/${WG_INTERFACE}.conf <<EOF
[Interface]
Address = ${SERVER_IP}/24
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
PostUp = ufw route allow in on ${WG_INTERFACE} out on ${NET_IFACE}; iptables -t nat -A POSTROUTING -o ${NET_IFACE} -j MASQUERADE
PostDown = ufw route delete allow in on ${WG_INTERFACE} out on ${NET_IFACE}; iptables -t nat -D POSTROUTING -o ${NET_IFACE} -j MASQUERADE
EOF

# Step 7: Create clients
for i in $(seq 1 $CLIENT_COUNT); do
  log "Creating client $i..."
  CLIENT_PRIVATE_KEY=$(wg genkey)
  CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)
  CLIENT_IP="10.66.66.$((i + 1))"
  CLIENT_CONF="/root/client${i}.conf"

  # Client config
  cat > $CLIENT_CONF <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_IP}/24
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = $(curl -s ifconfig.me):${SERVER_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
EOF

  # Add client to server config
  cat >> ${WG_CONF_DIR}/${WG_INTERFACE}.conf <<EOF

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${CLIENT_IP}/32
EOF

  # Display QR code for mobile apps
  log "QR code for Client ${i}:"
  qrencode -t ansiutf8 < $CLIENT_CONF
done

# Step 8: Enable and start WireGuard
log "Enabling and starting WireGuard..."
systemctl enable wg-quick@${WG_INTERFACE}
systemctl start wg-quick@${WG_INTERFACE}

log "=== WireGuard VPN setup complete! ==="
log "Server public key: ${SERVER_PUBLIC_KEY}"
log "Server config: ${WG_CONF_DIR}/${WG_INTERFACE}.conf"
log "Client configs: /root/client*.conf"
log "Use 'sudo wg show' to view connection status."
