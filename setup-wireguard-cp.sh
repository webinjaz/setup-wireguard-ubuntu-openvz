#!/bin/bash

set -e

WG_INTERFACE="wg0"
WG_PORT=51820
WG_SUBNET="10.0.0.1/24"
WG_CONF="/etc/wireguard/${WG_INTERFACE}.conf"

# Install dependencies
apt update && apt install -y golang-go wireguard-tools iproute2 iptables curl unzip

# Download wireguard-go
mkdir -p /opt/wireguard-go
cd /opt/wireguard-go
curl -LO https://github.com/WireGuard/wireguard-go/archive/refs/heads/master.zip
unzip master.zip
cd wireguard-go-master
go build
mv wireguard-go /usr/local/bin/

# Generate server keys
mkdir -p /etc/wireguard
umask 077
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
SERVER_PRIV_KEY=$(cat /etc/wireguard/server_private.key)

# Create WireGuard config
cat > "$WG_CONF" <<EOF
[Interface]
Address = ${WG_SUBNET}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -A FORWARD -o ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -D FORWARD -o ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o venet0 -j MASQUERADE
EOF

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Launch WireGuard-Go
nohup /usr/local/bin/wireguard-go ${WG_INTERFACE} &

# Apply config
wg-quick up ${WG_INTERFACE}

echo "✅ WireGuard-Go server is running on venet0."
echo "📌 Server public key:"
cat /etc/wireguard/server_public.key