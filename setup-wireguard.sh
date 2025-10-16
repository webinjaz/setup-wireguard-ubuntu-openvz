#!/bin/bash
# setup-wireguard.sh
# Robust WireGuard setup for Ubuntu 24.04 OpenVZ

set -e

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}[STEP 0] Fixing broken packages and configuring system...${NC}"
export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a || true
apt --fix-broken install -y
apt update
apt upgrade -y

echo -e "${GREEN}[STEP 1] Installing required packages...${NC}"
apt install -y curl git unzip ufw iptables wireguard-tools qrencode

echo -e "${GREEN}[STEP 2] Configuring firewall...${NC}"
ufw allow 22/tcp
ufw allow 51820/udp
ufw --force enable

echo -e "${GREEN}[STEP 3] Enabling IP forwarding...${NC}"
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf

echo -e "${GREEN}[STEP 4] Generating server and client keys...${NC}"
mkdir -p /etc/wireguard
cd /etc/wireguard
umask 077

# Server key
wg genkey | tee server_private.key | wg pubkey > server_public.key

# Client 1 key
wg genkey | tee client1_private.key | wg pubkey > client1_public.key

# Client 2 key
wg genkey | tee client2_private.key | wg pubkey > client2_public.key

echo -e "${GREEN}[STEP 5] Creating wg0 configuration...${NC}"
cat > wg0.conf <<EOF
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = $(cat server_private.key)
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $(ip route get 1.1.1.1 | awk '{print $5}') -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $(ip route get 1.1.1.1 | awk '{print $5}') -j MASQUERADE

[Peer]
PublicKey = $(cat client1_public.key)
AllowedIPs = 10.66.66.2/32

[Peer]
PublicKey = $(cat client2_public.key)
AllowedIPs = 10.66.66.3/32
EOF

echo -e "${GREEN}[STEP 6] Starting WireGuard service...${NC}"
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo -e "${GREEN}[STEP 7] Generating client QR codes...${NC}"
qrencode -t ansiutf8 < client1_private.key
qrencode -t ansiutf8 < client2_private.key

echo -e "${GREEN}[DONE] WireGuard setup completed.${NC}"
