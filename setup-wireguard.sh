#!/bin/bash
set -e

echo "[INFO] Starting system fix and WireGuard setup..."

# 1. Fix broken packages
echo "[INFO] Fixing broken packages..."
dpkg --configure -a || true
apt-get install -f -y

# Reconfigure tzdata carefully
echo "[INFO] Configuring tzdata..."
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure tzdata || true

# Fix any remaining broken dependencies
apt-get install -f -y
apt --fix-broken install -y

# Update & upgrade system
echo "[INFO] Updating system packages..."
apt update && apt upgrade -y

# 2. Install necessary packages
echo "[INFO] Installing required packages..."
apt install -y wireguard iproute2 curl vim systemd

# 3. Fix possible Python issues
echo "[INFO] Ensuring Python 3.12 is configured..."
dpkg --configure -a || true

# 4. Setup WireGuard
echo "[INFO] Setting up WireGuard..."
if modprobe wireguard 2>/dev/null; then
    echo "[INFO] Kernel supports WireGuard. Enabling wg-quick..."
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
else
    echo "[INFO] Kernel module not found. Using WireGuard-Go..."
    apt install -y wireguard-go
    wg-quick down wg0 2>/dev/null || true
    wireguard-go wg0
    wg setconf wg0 /etc/wireguard/wg0.conf

    # Ensure userspace interface starts on boot
    if ! grep -q "wireguard-go wg0" /etc/rc.local 2>/dev/null; then
        sed -i '/^exit 0/i wireguard-go wg0\nwg setconf wg0 /etc/wireguard/wg0.conf' /etc/rc.local
        chmod +x /etc/rc.local
    fi
fi

# 5. Show WireGuard status
echo "[INFO] WireGuard status:"
wg show

echo "[INFO] System fix and WireGuard setup completed!"
