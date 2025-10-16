#!/usr/bin/env bash
# WireGuard-go setup for Ubuntu 24.04 OpenVZ VPS
# Author: YourName
# Date: 2025-10-16

set -e

echo "[INFO] Starting WireGuard-go setup..."

# 1. Update system and install dependencies
echo "[STEP 1] Installing dependencies..."
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y git curl iproute2 iptables qrencode ufw build-essential unzip wget golang

# 2. Setup Go environment
GO_VERSION="1.25.3"
if ! go version | grep -q "$GO_VERSION"; then
    echo "[INFO] Installing Go $GO_VERSION..."
    wget -q https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz -O /tmp/go.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf /tmp/go.tar.gz
    export PATH=$PATH:/usr/local/go/bin
fi

# 3. Clone and build WireGuard-go
WG_DIR="/opt/wireguard-go"
if [ ! -d "$WG_DIR" ]; then
    echo "[STEP 2] Cloning WireGuard-go..."
    sudo git clone https://git.zx2c4.com/wireguard-go $WG_DIR
else
    echo "[INFO] WireGuard-go already cloned"
fi

echo "[STEP 3] Building WireGuard-go..."
cd $WG_DIR
sudo make
sudo cp wireguard-go /usr/local/bin/
sudo chmod +x /usr/local/bin/wireguard-go

# 4. Configure UFW
echo "[STEP 4] Configuring UFW..."
sudo ufw allow 51820/udp
sudo ufw allow OpenSSH
sudo ufw --force enable

# 5. Enable IP forwarding
echo "[STEP 5] Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# 6. Generate server and client keys
WG_CONF="/etc/wireguard/wg0.conf"
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

echo "[STEP 6] Generating keys..."
SERVER_PRIV=$(wg genkey)
SERVER_PUB=$(echo $SERVER_PRIV | wg pubkey)

CLIENT1_PRIV=$(wg genkey)
CLIENT1_PUB=$(echo $CLIENT1_PRIV | wg pubkey)

CLIENT2_PRIV=$(wg genkey)
CLIENT2_PUB=$(echo $CLIENT2_PRIV | wg pubkey)

# 7. Create WireGuard config
echo "[STEP 7] Creating wg0.conf..."
cat <<EOF | sudo tee $WG_CONF
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIV
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o venet0 -j MASQUERADE

[Peer]
PublicKey = $CLIENT1_PUB
AllowedIPs = 10.66.66.2/32

[Peer]
PublicKey = $CLIENT2_PUB
AllowedIPs = 10.66.66.3/32
EOF
sudo chmod 600 $WG_CONF

# 8. Create client configs
echo "[STEP 8] Creating client configs..."
CLIENT1_CONF="/etc/wireguard/client1.conf"
CLIENT2_CONF="/etc/wireguard/client2.conf"

cat <<EOF | sudo tee $CLIENT1_CONF
[Interface]
PrivateKey = $CLIENT1_PRIV
Address = 10.66.66.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $(curl -s https://api.ipify.org):51820
AllowedIPs = 0.0.0.0/0, ::/0
EOF

cat <<EOF | sudo tee $CLIENT2_CONF
[Interface]
PrivateKey = $CLIENT2_PRIV
Address = 10.66.66.3/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $(curl -s https://api.ipify.org):51820
AllowedIPs = 0.0.0.0/0, ::/0
EOF

# 9. Generate QR codes
echo "[STEP 9] Generating QR codes..."
qrencode -t ansiutf8 < $CLIENT2_CONF

# 10. Create systemd service
echo "[STEP 10] Creating systemd service..."
SERVICE_FILE="/etc/systemd/system/wg0.service"
cat <<EOF | sudo tee $SERVICE_FILE
[Unit]
Description=WireGuard-go VPN
After=network.target

[Service]
ExecStart=/usr/local/bin/wireguard-go wg0
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable wg0
sudo systemctl start wg0

echo "[DONE] WireGuard-go setup complete!"
echo "Client1 config: $CLIENT1_CONF"
echo "Client2 config: $CLIENT2_CONF (QR code above)"
