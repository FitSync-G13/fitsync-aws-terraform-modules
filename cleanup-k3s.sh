#!/bin/bash

# Cleanup script for K3s cluster
# Run this on master and worker nodes to completely remove K3s

echo "=== K3s Cleanup Script ==="
echo ""

# Detect if this is a master or worker node
if systemctl list-units --full -all | grep -q "k3s.service"; then
    NODE_TYPE="master"
    SERVICE="k3s"
    UNINSTALL_SCRIPT="/usr/local/bin/k3s-uninstall.sh"
elif systemctl list-units --full -all | grep -q "k3s-agent.service"; then
    NODE_TYPE="worker"
    SERVICE="k3s-agent"
    UNINSTALL_SCRIPT="/usr/local/bin/k3s-agent-uninstall.sh"
else
    echo "No K3s installation detected on this node"
    exit 0
fi

echo "Detected node type: $NODE_TYPE"
echo ""

# Stop the service
echo "Stopping $SERVICE..."
sudo systemctl stop $SERVICE 2>/dev/null || echo "Service already stopped"

# Run uninstall script if it exists
if [ -f "$UNINSTALL_SCRIPT" ]; then
    echo "Running uninstall script..."
    sudo $UNINSTALL_SCRIPT
else
    echo "Uninstall script not found, performing manual cleanup..."
fi

# Clean up directories
echo "Cleaning up directories..."
sudo rm -rf /var/lib/rancher/k3s
sudo rm -rf /etc/rancher/k3s
sudo rm -rf /var/lib/cni
sudo rm -rf /etc/cni
sudo rm -rf /opt/cni
sudo rm -rf /run/k3s
sudo rm -rf /run/flannel

# Clean up iptables rules
echo "Cleaning up iptables rules..."
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X

# Verify cleanup
echo ""
echo "=== Cleanup Complete ==="
echo "Verifying cleanup..."
systemctl status $SERVICE 2>&1 | grep -q "could not be found" && echo "✓ Service removed" || echo "✗ Service still exists"
[ ! -d /var/lib/rancher/k3s ] && echo "✓ K3s data directory removed" || echo "✗ K3s data directory still exists"
[ ! -d /etc/rancher/k3s ] && echo "✓ K3s config directory removed" || echo "✗ K3s config directory still exists"

echo ""
echo "Cleanup complete! You can now reinstall K3s."
