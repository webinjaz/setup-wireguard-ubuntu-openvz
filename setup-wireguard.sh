#!/bin/bash
set -e

echo "[INFO] Starting system fix and WireGuard setup..."

# 1. Set DEBIAN_FRONTEND to noninteractive to avoid prompts
export DEBIAN_FRONTEND=noninteractive
export TZ=Etc/UTC  # Default timezone to avoid tzdata prompt

# 2. Update package lists
apt update -y

# 3. Fix broken packages
echo "[INFO] Fixing broken packages..."
apt install -f -y || true
dpkg --configure -a || true

# 4. Reconfigure tzdata non-interactively
echo "[INFO] Configuring tzdata..."
ln -fs /usr/share/zoneinfo/$TZ /etc/localtime
dpkg-reconfigure -f noninteractive tzdata || true

# 5. Fix any remaining broken dependencies
apt --fix-broken install -y

# 6. Upgrade system safely
echo "[INFO] Upgrading system packages..."
apt upgrade -y

# 7. Install required packages
echo "[INFO] Installing required packages..."
apt install -y wireguard wireguard-tools iproute2 curl vim systemd

# 8. Ensure Python 3.12 is configured
dpkg --configure -a || true

# 9. WireGuard setup
echo "[INFO] Setting up WireGuard..."
if modprobe wireguard 2>/dev/null; then
    echo "[INFO] Kernel supports WireGuard. Enabling wg-quick..."
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0 || true
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

# 10. Show WireGuard status
echo "[INFO] WireGuard status:"
wg show || true

echo "[INFO] System fix and WireGuard setup completed!"
