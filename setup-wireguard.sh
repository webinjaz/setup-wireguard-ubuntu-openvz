#!/bin/bash
set -e

# ==========================================
# WireGuard Setup Script for Ubuntu 24.04
# Supports multiple clients, UFW, IP forwarding
# ==========================================

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}[STEP 1] Updating system...${NC}"
sudo apt update && sudo apt upgrade -y

echo -e "${GREEN}[STEP 2] Installing WireGuard and dependencies...${NC}"
sudo apt install -y wireguard wireguard-tools qrencode ufw

echo -e "${GREEN}[STEP 3] Configuring firewall...${NC}"
sudo ufw allow 51820/udp
sudo ufw allow OpenSSH
sudo ufw --force enable

echo -e "${GREEN}[STEP 4] Enabling IP forwarding...${NC}"
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -p

echo -e "${GREEN}[STEP 5] Creating WireGuard configuration directory...${NC}"
sudo mkdir -p /etc/wireguard
sudo chmod 700 /etc/wireguard

cd /etc/wireguard

echo -e "${GREEN}[STEP 6] Generating server keys...${NC}"
sudo wg genkey | sudo tee server_private.key | wg pubkey | sudo tee server_public.key

SERVER_PRIV=$(sudo cat server_private.key)

echo -e "${GREEN}[STEP 7] Creating wg0.conf...${NC}"
sudo bash -c "cat > /etc/wireguard/wg0.conf" <<EOL
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIV
SaveConfig = true
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $(ip route | grep default | awk '{print $5}') -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $(ip route | grep default | awk '{print $5}') -j MASQUERADE
EOL

sudo chmod 600 /etc/wireguard/wg0.conf

echo -e "${GREEN}[STEP 8] Starting WireGuard...${NC}"
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

echo -e "${GREEN}[STEP 9] Checking WireGuard status...${NC}"
sudo wg show

echo -e "${GREEN}WireGuard setup complete!${NC}"
echo -e "Your server public key is: $(sudo cat server_public.key)"
echo -e "You can now generate client configs and QR codes using wg genkey and qrencode."
