#!/bin/bash
set -euo pipefail

# RHEL Kubernetes Prerequisites Setup
# Run this script on ALL nodes (control-plane and workers)

echo "=== Setting up RHEL prerequisites for Kubernetes ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (or with sudo)" 
   exit 1
fi

# Prompt for node configuration
echo "Please configure the following for your environment:"
echo "1. Update the hostnames and IP addresses below"
echo "2. Ensure all nodes can reach each other"
echo ""

read -p "Enter hostname for this node (e.g., k8s-cp-1, k8s-w-1, k8s-w-2): " HOSTNAME
read -p "Enter control plane IP: " CP_IP
read -p "Enter worker 1 IP: " W1_IP  
read -p "Enter worker 2 IP: " W2_IP

# Set hostname
echo "Setting hostname to: $HOSTNAME"
hostnamectl set-hostname "$HOSTNAME"

# Update /etc/hosts with cluster nodes
echo "Updating /etc/hosts with cluster node information..."
cat >> /etc/hosts <<EOF

# Kubernetes cluster nodes
$CP_IP k8s-cp-1
$W1_IP k8s-w-1  
$W2_IP k8s-w-2
EOF

echo "Updated /etc/hosts:"
tail -4 /etc/hosts

# Disable swap (Kubernetes requirement)
echo "Disabling swap..."
swapoff -a
sed -ri '/\sswap\s/s/^/#/' /etc/fstab

# Load required kernel modules for Kubernetes networking
echo "Loading kernel modules for container networking..."
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Configure sysctl parameters for Kubernetes
echo "Configuring sysctl parameters for Kubernetes..."
cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

# Apply sysctl parameters
sysctl --system

# Disable SELinux (required for proper pod networking)
echo "Configuring SELinux for Kubernetes..."
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Configure firewall for Kubernetes
echo "Configuring firewall for Kubernetes..."
# Ensure firewalld is installed
if ! command -v firewall-cmd >/dev/null 2>&1; then
  echo "Installing firewalld..."
  dnf install -y firewalld || true
fi
systemctl enable --now firewalld || true

# Control plane ports
if [[ "$HOSTNAME" == *"cp"* ]] || [[ "$HOSTNAME" == *"control"* ]] || [[ "$HOSTNAME" == *"master"* ]]; then
    echo "Opening control plane ports..."
    firewall-cmd --permanent --add-port=6443/tcp    # Kubernetes API server
    firewall-cmd --permanent --add-port=2379-2380/tcp # etcd server client API
    firewall-cmd --permanent --add-port=10250/tcp   # Kubelet API
    firewall-cmd --permanent --add-port=10259/tcp   # kube-scheduler
    firewall-cmd --permanent --add-port=10257/tcp   # kube-controller-manager
fi

# Worker node ports (open on all nodes)
echo "Opening worker node ports..."
firewall-cmd --permanent --add-port=10250/tcp   # Kubelet API
firewall-cmd --permanent --add-port=30000-32767/tcp # NodePort Services

# Calico BGP port
firewall-cmd --permanent --add-port=179/tcp

# Reload firewall
firewall-cmd --reload

# Update system packages
echo "Updating system packages..."
dnf update -y

# Install required packages
echo "Installing required packages..."
dnf install -y \
    yum-utils \
    device-mapper-persistent-data \
    lvm2 \
    curl \
    wget \
    vim \
    git \
    htop \
    jq

echo ""
echo "=== RHEL prerequisites setup completed! ==="
echo ""
echo "Next steps:"
echo "1. Run this script on all other nodes"
echo "2. Run 01-install-containerd.sh on all nodes"
echo "3. Run 02-install-kubeadm.sh on all nodes"
echo ""
echo "Current hostname: $(hostname)"
echo "Swap status: $(swapon --show || echo 'No swap active')"
echo "IP forwarding: $(sysctl net.ipv4.ip_forward)"
