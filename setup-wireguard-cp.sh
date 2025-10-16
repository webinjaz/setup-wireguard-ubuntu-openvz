#!/bin/bash

set -e

WG_INTERFACE="wg0"
WG_PORT=51820
WG_SUBNET="10.0.0.1/24"
WG_CONF="/etc/wireguard/${WG_INTERFACE}.conf"

# Install dependencies silently
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y golang-go wireguard-tools iproute2 iptables curl unzip

# Download and build wireguard-go
mkdir -p /opt/wireguard-go
cd /opt/wireguard-go
rm -rf wireguard-go-master master.zip
curl -sSL https://github.com/WireGuard/wireguard-go/archive/refs/heads/master.zip -o master.zip
unzip -o -q master.zip
cd wireguard-go-master
go build -o /usr/local/bin/wireguard-go ./main.go

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

# Launch WireGuard-Go silently
nohup /usr/local/bin/wireguard-go ${WG_INTERFACE} >/dev/null 2>&1 &

# Apply config
wg-quick up ${WG_INTERFACE}

echo "✅ WireGuard-Go server is running on venet0."
echo "📌 Server public key:"
cat /etc/wireguard/server_public.key