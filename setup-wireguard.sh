#!/bin/bash
# =======================================================
# Ubuntu WireGuard + Web UI Auto Installer (Non-Active)
# =======================================================
# Tested on Ubuntu 24.04
# =======================================================

set -e
echo "[INFO] Starting WireGuard installation script..."

# -----------------------------
# Update system and fix broken packages
# -----------------------------
sudo apt-get update -y
sudo apt-get upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-broken tzdata
sudo dpkg --configure -a
sudo apt-get install -y wireguard qrencode ufw curl wget sqlite3

# -----------------------------
# WireGuard server setup
# -----------------------------
WG_CONF="/etc/wireguard/wg0.conf"
SERVER_PORT=51820
SERVER_IP=$(curl -s https://ipinfo.io/ip)
WG_NET="10.66.66.0/24"

echo "[INFO] Generating WireGuard keys..."
SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | wg pubkey)

sudo mkdir -p /etc/wireguard
sudo bash -c "cat > $WG_CONF" <<EOL
[Interface]
Address = ${WG_NET%.*}.1/24
ListenPort = $SERVER_PORT
PrivateKey = $SERVER_PRIV_KEY
SaveConfig = true
EOL

sudo chmod 600 $WG_CONF
echo "[INFO] WireGuard server config created at $WG_CONF"

# -----------------------------
# Firewall (UFW)
# -----------------------------
sudo ufw allow $SERVER_PORT/udp
sudo ufw allow OpenSSH
sudo ufw --force enable
echo "[INFO] Firewall configured"

# -----------------------------
# WireGuard Web UI
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
# Auto-config WireGuard UI admin credentials
# -----------------------------
WG_UI_DB="$WG_UI_DIR/wireguard-ui.db"
if [ ! -f $WG_UI_DB ]; then
    ADMIN_USER="admin"
    ADMIN_PASS=$(openssl rand -base64 16)

    # Launch WireGuard UI once to create DB
    sudo $WG_UI_DIR/wireguard-ui &
    sleep 5
    sudo pkill wireguard-ui

    # Insert user credentials into SQLite DB
    sudo sqlite3 $WG_UI_DB "INSERT INTO users (username, password_hash, is_admin) VALUES ('$ADMIN_USER', '\$(echo -n \"$ADMIN_PASS\" | sha256sum | awk '{print \$1}')', 1);"
fi

# -----------------------------
# Summary
# -----------------------------
echo "[INFO] ==================================================="
echo "[INFO] WireGuard server installed at $WG_CONF"
echo "[INFO] WireGuard is not active by default. Start with:"
echo "       sudo wg-quick up wg0"
echo "[INFO] WireGuard UI running at http://$SERVER_IP:5000"
echo "[INFO] WireGuard UI admin credentials:"
echo "       Username: $ADMIN_USER"
echo "       Password: $ADMIN_PASS"
echo "[INFO] ==================================================="
