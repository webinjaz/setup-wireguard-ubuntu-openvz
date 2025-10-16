#!/bin/bash
set -e

# -----------------------------
# Basic System Setup
# -----------------------------
export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Updating system..."
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y software-properties-common curl wget ufw gnupg lsb-release

# -----------------------------
# Fix tzdata and Python packages
# -----------------------------
echo "[INFO] Fixing broken packages..."
sudo apt --fix-broken install -y
sudo dpkg --configure -a
sudo apt install -f -y

# Force configure tzdata
echo "tzdata tzdata/Areas select Etc" | sudo debconf-set-selections
echo "tzdata tzdata/Zones/Etc select UTC" | sudo debconf-set-selections
sudo dpkg-reconfigure -f noninteractive tzdata

# Reconfigure Python packages if broken
sudo apt --fix-broken install -y

# -----------------------------
# Install WireGuard
# -----------------------------
echo "[INFO] Installing WireGuard..."
sudo apt install -y wireguard wireguard-tools

# Generate server keys if not exist
WG_DIR="/etc/wireguard"
sudo mkdir -p $WG_DIR
if [ ! -f $WG_DIR/server_private.key ]; then
    sudo wg genkey | sudo tee $WG_DIR/server_private.key | sudo wg pubkey | sudo tee $WG_DIR/server_public.key
fi

SERVER_PRIV_KEY=$(sudo cat $WG_DIR/server_private.key)
SERVER_PUB_KEY=$(sudo cat $WG_DIR/server_public.key)

# Default server config (non-active mode)
WG_CONF="$WG_DIR/wg0.conf"
sudo bash -c "cat > $WG_CONF" <<EOL
[Interface]
PrivateKey = $SERVER_PRIV_KEY
Address = 10.10.0.1/24
ListenPort = 51820
SaveConfig = true
EOL

sudo chmod 600 $WG_CONF
sudo systemctl enable wg-quick@wg0.service

# -----------------------------
# Setup UFW firewall for WireGuard
# -----------------------------
sudo ufw allow 51820/udp
sudo ufw --force enable

# -----------------------------
# Install WireGuard Web UI (WireGuard-UI)
# -----------------------------
echo "[INFO] Installing WireGuard UI..."
WG_UI_DIR="/opt/wireguard-ui"
sudo mkdir -p $WG_UI_DIR
cd $WG_UI_DIR
sudo wget https://github.com/ngoduykhanh/wireguard-ui/releases/latest/download/wireguard-ui-linux-amd64 -O wireguard-ui
sudo chmod +x wireguard-ui

# Create systemd service for WireGuard UI
sudo bash -c 'cat > /etc/systemd/system/wireguard-ui.service' <<EOL
[Unit]
Description=WireGuard Web UI
After=network.target

[Service]
Type=simple
ExecStart=/opt/wireguard-ui/wireguard-ui
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable wireguard-ui
sudo systemctl start wireguard-ui

# -----------------------------
# Auto-config admin credentials
# -----------------------------
WG_UI_DB="$WG_UI_DIR/wireguard-ui.db"
if [ ! -f $WG_UI_DB ]; then
    # Will auto create with default admin/admin on first run
    sudo $WG_UI_DIR/wireguard-ui &
    sleep 5
    sudo pkill wireguard-ui
fi

# -----------------------------
# Summary
# -----------------------------
echo "[INFO] WireGuard and WireGuard UI installed!"
echo "[INFO] Server wg0.conf located at: $WG_CONF"
echo "[INFO] Access WireGuard UI at http://<server_ip>:5000 (default admin/admin)"
echo "[INFO] WireGuard not started automatically (non-active mode). Use: sudo wg-quick up wg0"
