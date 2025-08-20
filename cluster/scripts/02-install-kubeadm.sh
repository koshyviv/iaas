#!/bin/bash
set -euo pipefail

# Install kubeadm, kubelet, and kubectl
# Run this script on ALL nodes (control-plane and workers)

echo "=== Installing kubeadm, kubelet, and kubectl ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (or with sudo)" 
   exit 1
fi

# Kubernetes version to install
K8S_VERSION="v1.33"

echo "Installing Kubernetes version: $K8S_VERSION"

# Add Kubernetes repository
echo "Adding Kubernetes repository..."
cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl
EOF

# Install Kubernetes components
echo "Installing kubelet, kubeadm, and kubectl..."
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

# Enable kubelet service (it will start after kubeadm init/join)
echo "Enabling kubelet service..."
systemctl enable kubelet

# Configure kubelet to use the correct cgroup driver
echo "Configuring kubelet for systemd cgroups..."
mkdir -p /etc/systemd/system/kubelet.service.d
cat > /etc/systemd/system/kubelet.service.d/20-cgroup-driver.conf <<EOF
[Service]
Environment="KUBELET_CGROUP_ARGS=--cgroup-driver=systemd"
EOF

systemctl daemon-reload

# Verify installation
echo "Verifying Kubernetes installation..."
echo "kubelet version: $(kubelet --version)"
echo "kubeadm version: $(kubeadm version --output=short)"
echo "kubectl version: $(kubectl version --client --output=yaml | grep gitVersion)"

# Check if kubelet service is enabled
if systemctl is-enabled kubelet >/dev/null 2>&1; then
    echo "✓ kubelet service is enabled"
else
    echo "✗ kubelet service is not enabled"
    exit 1
fi

# Pre-pull Kubernetes images (optional but recommended)
echo ""
read -p "Pre-pull Kubernetes images? This will download ~500MB but speeds up cluster init (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Pre-pulling Kubernetes images..."
    kubeadm config images pull --kubernetes-version=$K8S_VERSION
    echo "✓ Images pre-pulled successfully"
fi

echo ""
echo "=== Kubernetes components installation completed! ==="
echo ""
echo "Installed versions:"
kubeadm version --output=short
kubelet --version
kubectl version --client --short
echo ""
echo "Next steps:"
echo "- On control-plane node: Run 10-controlplane-init.sh"
echo "- On worker nodes: Wait for join command from control-plane"
echo ""
echo "Note: kubelet service is enabled but not started (this is normal)"
echo "      It will start automatically after kubeadm init/join"
