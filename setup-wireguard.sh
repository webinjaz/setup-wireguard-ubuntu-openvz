#!/bin/bash
# WireGuard VPN Setup Script for Ubuntu 24.04 (OpenVZ compatible)
# Includes tzdata and Python fix

set -e

# -----------------------------------------
# 1. Prevent interactive prompts (tzdata)
# -----------------------------------------
export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Setting default timezone to UTC..."
ln -fs /usr/share/zoneinfo/Etc/UTC /etc/localtime
dpkg-reconfigure --frontend noninteractive tzdata || true

# -----------------------------------------
# 2. Fix broken packages
# -----------------------------------------
echo "[INFO] Updating system packages and fixing broken packages..."
apt-get update
apt-get install -f -y
dpkg --configure -a || true

# -----------------------------------------
# 3. Ensure essential packages are installed
# -----------------------------------------
echo "[INFO] Installing dependencies..."
apt-get install -y \
    tzdata \
    python3.12 \
    libpython3.12-stdlib \
    libpython3.12t64 \
    vim \
    curl \
    wget \
    software-properties-common \
    gnupg \
    iptables \
    iproute2

# -----------------------------------------
# 4. Detect public network interface
# -----------------------------------------
echo "[INFO] Detecting public network interface..."
PUBLIC_IFACE=$(ip -o -4 route show to default | awk '{print $5}')
echo "[INFO] Public interface detected: $PUBLIC_IFACE"

# -----------------------------------------
# 5. Install WireGuard
# -----------------------------------------
echo "[INFO] Installing WireGuard..."
apt-get install -y wireguard wireguard-tools

# -----------------------------------------
# 6. Enable IP forwarding
# -----------------------------------------
echo "[INFO] Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf

# -----------------------------------------
# 7. Create WireGuard server keys
# -----------------------------------------
WG_DIR="/etc/wireguard"
mkdir -p $WG_DIR
wg genkey | tee $WG_DIR/privatekey | wg pubkey > $WG_DIR/publickey

# -----------------------------------------
# 8. Create basic WireGuard config
# -----------------------------------------
PRIVATE_KEY=$(cat $WG_DIR/privatekey)
cat > $WG_DIR/wg0.conf <<EOL
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = $PRIVATE_KEY
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $PUBLIC_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $PUBLIC_IFACE -j MASQUERADE
SaveConfig = true
EOL

chmod 600 $WG_DIR/wg0.conf

# -----------------------------------------
# 9. Enable and start WireGuard
# -----------------------------------------
echo "[INFO] Enabling and starting WireGuard..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo "[INFO] WireGuard installation complete!"
echo "Server public key: $(cat $WG_DIR/publickey)"
echo "Configuration file: $WG_DIR/wg0.conf"
