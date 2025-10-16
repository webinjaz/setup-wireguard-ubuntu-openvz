#!/bin/bash
# setup-wireguard.sh
# Fully automated WireGuard setup for Ubuntu 24.04 OpenVZ VPS

set -euo pipefail

WG_CONF="/etc/wireguard/wg0.conf"
CLIENT_DIR="/root"
SERVER_SUBNET="10.66.66.0/24"
SERVER_PORT=51820
CLIENT_COUNT=2
WG_INTERFACE="wg0"

log() { echo "[`date '+%Y-%m-%d %H:%M:%S'`] $*"; }

# -------------------------------
# Step 0: Non-interactive setup
# -------------------------------
log "Step 0: Setting non-interactive mode for apt..."
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

# -------------------------------
# Step 1: Fix broken packages and tzdata
# -------------------------------
log "Step 1: Fixing broken packages and tzdata..."
sudo apt update -y || true
sudo apt upgrade -y || true
sudo apt install -y --no-install-recommends tzdata || true
sudo dpkg --configure -a || true
sudo apt --fix-broken install -y || true
sudo ln -fs /usr/share/zoneinfo/UTC /etc/localtime
sudo dpkg-reconfigure --frontend noninteractive tzdata

# -------------------------------
# Step 2: Install WireGuard and dependencies
# -------------------------------
log "Step 2: Installing WireGuard and tools..."
sudo apt install -y --no-install-recommends wireguard-tools qrencode ufw iproute2 iptables curl

# -------------------------------
# Step 3: Detect public interface
# -------------------------------
PUBLIC_INTERFACE=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
log "Detected public interface: $PUBLIC_INTERFACE"

# -------------------------------
# Step 4: Configure firewall
# -------------------------------
log "Step 4: Configuring UFW..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow ${SERVER_PORT}/udp
sudo ufw --force enable

# -------------------------------
# Step 5: Enable IP forwarding
# -------------------------------
log "Step 5: Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv6.conf.all.forwarding=0
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# -------------------------------
# Step 6: Generate server keys
# -------------------------------
SERVER_PRIV_KEY_FILE="/etc/wireguard/server_private.key"
SERVER_PUB_KEY_FILE="/etc/wireguard/server_public.key"

if [ ! -f "$SERVER_PRIV_KEY_FILE" ]; then
    log "Step 6: Generating server keys..."
    sudo mkdir -p /etc/wireguard
    umask 077
    sudo wg genkey | sudo tee $SERVER_PRIV_KEY_FILE | sudo wg pubkey | sudo tee $SERVER_PUB_KEY_FILE
else
    log "Server keys already exist, skipping..."
fi

SERVER_PRIVATE_KEY=$(sudo cat $SERVER_PRIV_KEY_FILE)
SERVER_PUBLIC_KEY=$(sudo cat $SERVER_PUB_KEY_FILE)

# -------------------------------
# Step 7: Generate client keys
# -------------------------------
log "Step 7: Generating client keys..."
declare -a CLIENT_PRIVATE_KEYS
declare -a CLIENT_PUBLIC_KEYS
for i in $(seq 1 $CLIENT_COUNT); do
    PRIV_FILE="${CLIENT_DIR}/client${i}_private.key"
    PUB_FILE="${CLIENT_DIR}/client${i}_public.key"
    if [ ! -f "$PRIV_FILE" ]; then
        wg genkey | tee "$PRIV_FILE" | wg pubkey | tee "$PUB_FILE"
    fi
    CLIENT_PRIVATE_KEYS[$i]=$(cat $PRIV_FILE)
    CLIENT_PUBLIC_KEYS[$i]=$(cat $PUB_FILE)
done

# -------------------------------
# Step 8: Create server config
# -------------------------------
log "Step 8: Creating server config..."
sudo mkdir -p /etc/wireguard
umask 077
{
echo "[Interface]"
echo "Address = 10.66.66.1/24"
echo "ListenPort = ${SERVER_PORT}"
echo "PrivateKey = ${SERVER_PRIVATE_KEY}"
echo "PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${PUBLIC_INTERFACE} -j MASQUERADE"
echo "PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${PUBLIC_INTERFACE} -j MASQUERADE"
for i in $(seq 1 $CLIENT_COUNT); do
    echo "[Peer]"
    echo "PublicKey = ${CLIENT_PUBLIC_KEYS[$i]}"
    echo "AllowedIPs = 10.66.66.$((i+1))/32"
done
} | sudo tee $WG_CONF
sudo chmod 600 $WG_CONF

# -------------------------------
# Step 9: Create client configs and QR codes
# -------------------------------
log "Step 9: Creating client configs and QR codes..."
for i in $(seq 1 $CLIENT_COUNT); do
    CLIENT_CONF="${CLIENT_DIR}/client${i}.conf"
    CLIENT_IP="10.66.66.$((i+1))/24"
    {
    echo "[Interface]"
    echo "PrivateKey = ${CLIENT_PRIVATE_KEYS[$i]}"
    echo "Address = $CLIENT_IP"
    echo "DNS = 1.1.1.1"
    echo ""
    echo "[Peer]"
    echo "PublicKey = $SERVER_PUBLIC_KEY"
    echo "Endpoint = $(curl -s ifconfig.me):${SERVER_PORT}"
    echo "AllowedIPs = 0.0.0.0/0, ::/0"
    } > $CLIENT_CONF
    log "Client ${i} config saved: $CLIENT_CONF"
    log "QR code for mobile app:"
    qrencode -t ansiutf8 < $CLIENT_CONF
done

# -------------------------------
# Step 10: Enable WireGuard service
# -------------------------------
log "Step 10: Enabling WireGuard service..."
sudo systemctl enable wg-quick@$WG_INTERFACE
sudo systemctl start wg-quick@$WG_INTERFACE

log "WireGuard setup complete!"
log "Use 'sudo wg show' to check VPN status."
