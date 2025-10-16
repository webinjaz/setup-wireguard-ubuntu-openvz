#!/bin/bash
set -e

echo "🔍 Step 1: Installing OpenVPN and Easy-RSA"
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y openvpn easy-rsa iptables curl

echo "📁 Step 2: Setting Up Easy-RSA PKI"
make-cadir /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa
./easyrsa init-pki
echo -ne '\n' | ./easyrsa build-ca nopass
./easyrsa gen-req server nopass
./easyrsa sign-req server server <<< yes
./easyrsa gen-dh
openvpn --genkey --secret ta.key
./easyrsa gen-req client nopass
./easyrsa sign-req client client <<< yes

echo "📦 Step 3: Copying Certificates and Keys"
cp pki/ca.crt pki/private/server.key pki/issued/server.crt pki/dh.pem ta.key /etc/openvpn
cp pki/ca.crt pki/private/client.key pki/issued/client.crt ta.key /etc/openvpn/client/

echo "🧾 Step 4: Creating Server Config"
cat > /etc/openvpn/server.conf <<EOF
port 1194
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
keepalive 10 120
cipher AES-256-CBC
persist-key
persist-tun
status openvpn-status.log
verb 3
EOF

echo "🔧 Step 5: Enabling IP Forwarding and NAT"
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o venet0 -j MASQUERADE

echo "🚀 Step 6: Starting OpenVPN Server"
systemctl enable openvpn@server
systemctl start openvpn@server

echo "📁 Step 7: Creating Client Profile"
PUBLIC_IP=$(curl -s https://ipinfo.io/ip)
mkdir -p /etc/openvpn/client
cat > /etc/openvpn/client/client.ovpn <<EOF
client
dev tun
proto udp
remote ${PUBLIC_IP} 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3
<ca>
$(cat /etc/openvpn/client/ca.crt)
</ca>
<cert>
$(cat /etc/openvpn/client/client.crt)
</cert>
<key>
$(cat /etc/openvpn/client/client.key)
</key>
<tls-auth>
$(cat /etc/openvpn/client/ta.key)
</tls-auth>
key-direction 1
EOF

echo "✅ OpenVPN setup complete!"
echo "📄 Client config saved to: /etc/openvpn/client/client.ovpn"