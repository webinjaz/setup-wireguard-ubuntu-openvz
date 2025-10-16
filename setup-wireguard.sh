#!/bin/bash
#==============================================
# WireGuard VPN Setup Script for Ubuntu 24.04
# Auto-detects kernel module or falls back to wireguard-go
# Compatible with OpenVZ/VM environments
#==============================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export TZ=Etc/UTC

log() { echo -e "[INFO] $1"; }

detect_interface() {
    ip route | grep '^default' | awk '{print $5}' | head -n1
}

fix_packages() {
    log "Fixing broken packages..."
    echo "tzdata tzdata/Areas select Etc" | debconf-set-selections
    echo "tzdata tzdata/Zones/Etc select UTC" | debconf-set-selections
    apt-get install -f -y
    dpkg --configure -a
}

update_system() {
    log "Updating system packages..."
    apt-get update -y
    apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
}

install_dependencies() {
    log "Installing required packages..."
    apt-get install -y --no-install-recommends \
        wireguard-tools qrencode iptables-persistent ufw curl wget git iproute2 resolvconf python3 python3-pip vim
}

install_wireguard_go() {
    if ! command -v wireguard-go &> /dev/null; then
        log "Installing wireguard-go..."
        apt-get install -y golang
        go install github.com/WireGuard/wireguard-go@latest
        export PATH=$PATH:$(go env GOPATH)/bin
    fi
}

enable_ip_forwarding() {
    log "Enabling IP forwarding..."
    sysctl -w net.ipv4.ip_forward=1
    sysctl -w net.ipv6.conf.all.forwarding=1
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
}

configure_firewall() {
    local iface=$1
    log "Configuring UFW firewall..."
    ufw allow 22/tcp
    ufw allow 51820/udp
    ufw disable || true
    echo "y" | ufw enable
}

generate_keys() {
    local prefix=$1
    local dir=$2
    mkdir -p "$dir"
    wg genkey | tee "$dir/${prefix}_private.key" | wg pubkey > "$dir/${prefix}_public.key"
}

create_server_conf() {
    local iface=$1
    local server_priv=$2
    local server_pub=$3
    local client1_pub=$4
    local client2_pub=$5
    mkdir -p /etc/wireguard/clients

    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.66.66.1/24, fd86:ea04:1115::1/64
ListenPort = 51820
PrivateKey = $(cat $server_priv)
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $iface -j MASQUERADE; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o $iface -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $iface -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o $iface -j MASQUERADE
SaveConfig = true

[Peer]
# Client 1
PublicKey = $(cat $client1_pub)
AllowedIPs = 10.66.66.2/32, fd86:ea04:1115::2/128

[Peer]
# Client 2
PublicKey = $(cat $client2_pub)
AllowedIPs = 10.66.66.3/32, fd86:ea04:1115::3/128
EOF

    chmod 600 /etc/wireguard/wg0.conf
}

create_client_conf() {
    local name=$1
    local client_priv=$2
    local server_pub=$3
    local server_ip=$4
    local last_octet=$5
    cat > /etc/wireguard/clients/${name}.conf <<EOF
[Interface]
PrivateKey = $(cat $client_priv)
Address = 10.66.66.${last_octet}/24, fd86:ea04:1115::${last_octet}/64
DNS = 1.1.1.1

[Peer]
PublicKey = $(cat $server_pub)
Endpoint = ${server_ip}:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
}

display_qr() {
    local conf=$1
    log "QR code for $(basename $conf):"
    qrencode -t ansiutf8 < "$conf"
}

enable_service() {
    log "Enabling wg-quick@wg0 service..."
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
}

#-------------------------------
# Main Script
#-------------------------------
log "Detecting public network interface..."
PUBLIC_IFACE=$(detect_interface)
log "Public interface detected: $PUBLIC_IFACE"

fix_packages
update_system
install_dependencies
enable_ip_forwarding
configure_firewall "$PUBLIC_IFACE"

# Check for WireGuard kernel module
if modprobe wireguard &> /dev/null; then
    log "WireGuard kernel module detected, using kernel module."
else
    log "Kernel module not available. Using wireguard-go."
    install_wireguard_go
    # Create a systemd service for wireguard-go userspace
    cat > /etc/systemd/system/wg-go@.service <<EOF
[Unit]
Description=WireGuard userspace interface %i
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wireguard-go %i
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable wg-go@wg0
    systemctl start wg-go@wg0
fi

# Generate server and client keys
generate_keys server /etc/wireguard
generate_keys client1 /etc/wireguard/clients
generate_keys client2 /etc/wireguard/clients

# Create configs
create_server_conf \
    "$PUBLIC_IFACE" \
    /etc/wireguard/server_private.key \
    /etc/wireguard/server_public.key \
    /etc/wireguard/clients/client1_public.key \
    /etc/wireguard/clients/client2_public.key

PUBLIC_IP=$(curl -s ifconfig.me)
create_client_conf client1 /etc/wireguard/clients/client1_private.key /etc/wireguard/server_public.key "$PUBLIC_IP" 2
create_client_conf client2 /etc/wireguard/clients/client2_private.key /etc/wireguard/server_public.key "$PUBLIC_IP" 3

# Display QR codes for clients
display_qr /etc/wireguard/clients/client1.conf
display_qr /etc/wireguard/clients/client2.conf

enable_service

cat <<EOF

WireGuard setup completed with automatic kernel module detection!

Commands:
  sudo systemctl start wg-quick@wg0
  sudo systemctl stop wg-quick@wg0
  sudo systemctl status wg-quick@wg0
  sudo wg show

Client configs are in /etc/wireguard/clients/
Use the QR codes above to connect mobile clients.

EOF
