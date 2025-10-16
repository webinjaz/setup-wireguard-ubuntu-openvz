#!/bin/bash
set -e

echo "🔍 Step 1: Preparing Environment Variables"
WG_INTERFACE="wg0"
WG_PORT=51820
WG_SUBNET="10.0.0.1/24"
WG_CLIENT_IP="10.0.0.2"
WG_CONF="/etc/wireguard/${WG_INTERFACE}.conf"
WG_CLIENT_CONF="/etc/wireguard/client.conf"

echo "🌐 Step 2: Installing Required Packages"
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y curl unzip iproute2 iptables wireguard-tools golang-go

echo "📥 Step 3: Downloading and Building wireguard-go"
mkdir -p /opt/wireguard-go
cd /opt/wireguard-go
rm -rf wireguard-go-master master.zip
curl -sSL https://github.com/WireGuard/wireguard-go/archive/refs/heads/master.zip -o master.zip
unzip -o -q master.zip
cd wireguard-go-master
go build -o /usr/local/bin/wireguard-go ./main.go

echo "🌍 Step 4: Detecting Public IP"
PUBLIC_IP=$(curl -s https://ipinfo.io/ip)

echo "🔐 Step 5: Generating Server and Client Keys"
mkdir -p /etc/wireguard
umask 077
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
wg genkey | tee /etc/wireguard/client_private.key | wg pubkey > /etc/wireguard/client_public.key
SERVER_PRIV_KEY=$(cat /etc/wireguard/server_private.key)
SERVER_PUB_KEY=$(cat /etc/wireguard/server_public.key)
CLIENT_PRIV_KEY=$(cat /etc/wireguard/client_private.key)
CLIENT_PUB_KEY=$(cat /etc/wireguard/client_public.key)

echo "🧾 Step 6: Creating Server Configuration"
cat > "$WG_CONF" <<EOF
[Interface]
Address = ${WG_SUBNET}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -A FORWARD -o ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -D FORWARD -o ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o venet0 -j MASQUERADE

[Peer]
PublicKey = ${CLIENT_PUB_KEY}
AllowedIPs = ${WG_CLIENT_IP}/32
EOF

echo "🔧 Step 7: Enabling IP Forwarding"
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

echo "🚀 Step 8: Starting wireguard-go and Applying Config"
nohup /usr/local/bin/wireguard-go ${WG_INTERFACE} >/dev/null 2>&1 &
sleep 2
wg-quick up ${WG_INTERFACE}

echo "📁 Step 9: Generating Client Configuration"
cat > "$WG_CLIENT_CONF" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${WG_CLIENT_IP}/24
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUB_KEY}
Endpoint = ${PUBLIC_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

echo "✅ Setup Complete!"
echo "🌐 Server IP: ${PUBLIC_IP}"
echo "🔑 Server Public Key: ${SERVER_PUB_KEY}"
echo "📄 Client config saved to: ${WG_CLIENT_CONF}"