#!/bin/bash
set -euo pipefail

# Install containerd with systemd cgroups
# Run this script on ALL nodes (control-plane and workers)

echo "=== Installing containerd with systemd cgroups ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (or with sudo)" 
   exit 1
fi

# Add Docker repository (containerd is distributed through Docker repos)
echo "Adding Docker repository for containerd..."
dnf install -y yum-utils
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Install containerd
echo "Installing containerd..."
dnf install -y containerd.io

# Generate default containerd configuration
echo "Generating containerd configuration..."
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Configure containerd to use systemd cgroups (required for Kubernetes)
echo "Configuring containerd to use systemd cgroups..."
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Ensure the CRI plugin is enabled
echo "Verifying CRI plugin is enabled..."
if ! grep -q "disabled_plugins.*cri" /etc/containerd/config.toml; then
    echo "CRI plugin is enabled (good)"
else
    echo "ERROR: CRI plugin appears to be disabled. Please check containerd configuration."
    exit 1
fi

# Start and enable containerd
echo "Starting and enabling containerd service..."
systemctl daemon-reload
systemctl enable --now containerd

# Verify containerd is running
echo "Verifying containerd status..."
systemctl status containerd --no-pager -l

# Test containerd functionality
echo "Testing containerd functionality..."
if ctr version >/dev/null 2>&1; then
    echo "✓ containerd is working correctly"
    ctr version
else
    echo "✗ containerd test failed"
    exit 1
fi

# Display containerd configuration summary
echo ""
echo "=== Containerd installation completed! ==="
echo ""
echo "Configuration summary:"
echo "- Runtime: containerd"
echo "- Cgroup driver: systemd"
echo "- CRI plugin: enabled"
echo "- Service status: $(systemctl is-active containerd)"
echo ""
echo "Next step: Run 02-install-kubeadm.sh on all nodes"
