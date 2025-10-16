#!/bin/bash
# setup-wireguard.sh
# Fully automated WireGuard-go VPN setup for Ubuntu 24.04 on OpenVZ

set -e

# -----------------------
# CONFIGURATION VARIABLES
# -----------------------
WG_INTERFACE="wg0"
WG_PORT=51820
VPN_SUBNET="10.66.66.0/24"
WG_DIR="/etc/wireguard"
SERVER_PRIVATE_KEY_FILE="$WG_DIR/server_private.key"
SERVER_PUBLIC_KEY_FILE="$WG_DIR/server_public.key"
CLIENT1_NAME="laptop"
CLIENT2_NAME="mobile"

# -----------------------
# FUNCTION: INFO PRINT
# -----------------------
log() { echo -e "[INFO] $1"; }

# -----------------------
# STEP 1: SYSTEM UPDATE & DEPENDENCIES
# -----------------------
log "Updating system and installing dependencies..."
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    git curl iproute2 iptables qrencode ufw build-essential unzip wget golang wireguard-tools

# -----------------------
# STEP 2: ENABLE IP FORWARDING
# -----------------------
log "Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv6.conf.all.forwarding=0
sudo bash -c 'echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf'
sudo bash -c 'echo "net.ipv6.conf.all.forwarding=0" >> /etc/sysctl.conf'

# -----------------------
# STEP 3: FIREWALL CONFIG
# -----------------------
log "Configuring UFW firewall..."
sudo ufw allow $WG_PORT/udp
sudo ufw allow OpenSSH
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable

# -----------------------
# STEP 4: INSTALL WIREGUARD-GO
# -----------------------
log "Installing WireGuard-go..."
cd /tmp
if [ ! -d wireguard-go ]; then
    git clone https://git.zx2c4.com/wireguard-go
fi
cd wireguard-go
make
sudo cp wireguard-go /usr/local/bin/
sudo chmod +x /usr/local/bin/wireguard-go

# -----------------------
# STEP 5: GENERATE SERVER AND CLIENT KEYS
# -----------------------
mkdir -p $WG_DIR
log "[STEP 6] Generating keys..."
wg genkey | tee $SERVER_PRIVATE_KEY_FILE | wg pubkey > $SERVER_PUBLIC_KEY_FILE

CLIENT1_PRIVATE=$(wg genkey)
CLIENT1_PUBLIC=$(echo $CLIENT1_PRIVATE | wg pubkey)
CLIENT2_PRIVATE=$(wg genkey)
CLIENT2_PUBLIC=$(echo $CLIENT2_PRIVATE | wg pubkey)

# -----------------------
# STEP 6: CREATE SERVER CONFIG
# -----------------------
log "[STEP 7] Creating $WG_INTERFACE.conf..."
sudo tee $WG_DIR/$WG_INTERFACE.conf > /dev/null <<EOL
[Interface]
Address = 10.66.66.1/24
ListenPort = $WG_PORT
PrivateKey = $(cat $SERVER_PRIVATE_KEY_FILE)
PostUp = iptables -A FORWARD -i $WG_INTERFACE -j ACCEPT; iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE
PostDown = iptables -D FORWARD -i $WG_INTERFACE -j ACCEPT; iptables -t nat -D POSTROUTING -o venet0 -j MASQUERADE

[Peer]
PublicKey = $CLIENT1_PUBLIC
AllowedIPs = 10.66.66.2/32

[Peer]
PublicKey = $CLIENT2_PUBLIC
AllowedIPs = 10.66.66.3/32
EOL

sudo chmod 600 $WG_DIR/$WG_INTERFACE.conf

# -----------------------
# STEP 7: CREATE CLIENT CONFIGS
# -----------------------
log "[STEP 8] Creating client configuration files..."
mkdir -p ~/wg-clients

cat > ~/wg-clients/$CLIENT1_NAME.conf <<EOL
[Interface]
PrivateKey = $CLIENT1_PRIVATE
Address = 10.66.66.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = $(cat $SERVER_PUBLIC_KEY_FILE)
Endpoint = $(curl -s ifconfig.me):$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOL

cat > ~/wg-clients/$CLIENT2_NAME.conf <<EOL
[Interface]
PrivateKey = $CLIENT2_PRIVATE
Address = 10.66.66.3/24
DNS = 1.1.1.1

[Peer]
PublicKey = $(cat $SERVER_PUBLIC_KEY_FILE)
Endpoint = $(curl -s ifconfig.me):$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOL

log "[INFO] Generating QR code for mobile client..."
qrencode -t ansiutf8 < ~/wg-clients/$CLIENT2_NAME.conf

# -----------------------
# STEP 8: CREATE SYSTEMD SERVICE
# -----------------------
log "[STEP 9] Creating systemd service..."
sudo tee /etc/systemd/system/$WG_INTERFACE.service > /dev/null <<EOL
[Unit]
Description=WireGuard-go VPN
After=network.target

[Service]
ExecStart=/usr/local/bin/wireguard-go $WG_INTERFACE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable $WG_INTERFACE
sudo systemctl start $WG_INTERFACE

# -----------------------
# STEP 9: FINISHED
# -----------------------
log "[SUCCESS] WireGuard setup completed!"
log "Client configs are in ~/wg-clients"
log "Use 'sudo systemctl status $WG_INTERFACE' to check WireGuard service."
