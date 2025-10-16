#!/bin/bash
set -e

# -----------------------------
# WireGuard Automatic Setup
# Compatible: Ubuntu 24.04
# -----------------------------

echo "[STEP 0] Fixing tzdata and broken packages..."
export DEBIAN_FRONTEND=noninteractive
export TZ=Etc/UTC

apt update -y
apt install -y tzdata
dpkg --configure -a
apt --fix-broken install -y
echo "[STEP 0] Done."

# -----------------------------
echo "[STEP 1] Updating system..."
apt update -y && apt upgrade -y

# -----------------------------
echo "[STEP 2] Installing required packages..."
apt install -y wireguard-tools qrencode iptables-persistent git curl unzip build-essential

# -----------------------------
echo "[STEP 3] Installing WireGuard-go (userspace)"
WG_GO_BIN="/usr/local/bin/wireguard-go"

if ! command -v wireguard-go &>/dev/null; then
    echo "[STEP 3] Downloading and installing wireguard-go..."
    cd /tmp
    WG_VERSION="0.0.20250522"
    curl -LO "https://git.zx2c4.com/wireguard-go/snapshot/wireguard-go-${WG_VERSION}.zip"
    unzip "wireguard-go-${WG_VERSION}.zip"
    cd wireguard-go-${WG_VERSION}
    make
    mv wireguard-go $WG_GO_BIN
    chmod +x $WG_GO_BIN
    echo "[STEP 3] wireguard-go installed at $WG_GO_BIN"
else
    echo "[STEP 3] wireguard-go already installed."
fi

# -----------------------------
echo "[STEP 4] Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
sed -i '/net.ipv4.ip_forward/s/^#//g' /etc/sysctl.conf
sed -i '/net.ipv6.conf.all.forwarding/s/^#//g' /etc/sysctl.conf
sysctl -p

# -----------------------------
echo "[STEP 5] Configuring firewall..."
ufw allow 22/tcp
ufw allow 51820/udp
ufw --force enable

# -----------------------------
echo "[STEP 6] Generating server and client keys..."
WG_CONF_DIR="/etc/wireguard"
mkdir -p $WG_CONF_DIR
chmod 700 $WG_CONF_DIR

SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(echo $SERVER_PRIV_KEY | wg pubkey)

CLIENT1_PRIV_KEY=$(wg genkey)
CLIENT1_PUB_KEY=$(echo $CLIENT1_PRIV_KEY | wg pubkey)

CLIENT2_PRIV_KEY=$(wg genkey)
CLIENT2_PUB_KEY=$(echo $CLIENT2_PRIV_KEY | wg pubkey)

# -----------------------------
echo "[STEP 7] Creating wg0.conf..."
cat > $WG_CONF_DIR/wg0.conf <<EOF
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIV_KEY
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o venet0 -j MASQUERADE

[Peer]
PublicKey = $CLIENT1_PUB_KEY
AllowedIPs = 10.66.66.2/32

[Peer]
PublicKey = $CLIENT2_PUB_KEY
AllowedIPs = 10.66.66.3/32
EOF

chmod 600 $WG_CONF_DIR/wg0.conf

# -----------------------------
echo "[STEP 8] Creating systemd service..."
cat > /etc/systemd/system/wg0.service <<EOF
[Unit]
Description=WireGuard-go VPN
After=network.target

[Service]
Type=simple
ExecStart=$WG_GO_BIN wg0
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wg0.service
systemctl start wg0.service

# -----------------------------
echo "[STEP 9] Generating client QR codes..."
mkdir -p $WG_CONF_DIR/clients

for i in 1 2; do
cat > $WG_CONF_DIR/clients/client${i}.conf <<EOF
[Interface]
PrivateKey = \${CLIENT${i}_PRIV_KEY}
Address = 10.66.66.$((i+1))/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB_KEY
Endpoint = $(curl -s ifconfig.me):51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

qrencode -t ansiutf8 < $WG_CONF_DIR/clients/client${i}.conf
done

echo "[DONE] WireGuard VPN setup complete!"
echo "Client configs are in $WG_CONF_DIR/clients/"
