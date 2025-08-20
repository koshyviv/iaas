#!/bin/bash
set -euo pipefail

# Initialize Kubernetes control plane
# Run this script ONLY on the control-plane node

echo "=== Initializing Kubernetes Control Plane ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (or with sudo)" 
   exit 1
fi

# Get control plane IP address
echo "Detecting control plane IP address..."
CONTROL_PLANE_IP=$(hostname -I | awk '{print $1}')
echo "Detected IP: $CONTROL_PLANE_IP"

read -p "Is this the correct control plane IP? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter the correct control plane IP: " CONTROL_PLANE_IP
fi

# Pod network CIDR (Calico default)
POD_NETWORK_CIDR="192.168.0.0/16"

echo ""
echo "Control plane configuration:"
echo "- Control plane IP: $CONTROL_PLANE_IP"
echo "- Pod network CIDR: $POD_NETWORK_CIDR"
echo "- Kubernetes version: $(kubeadm version --output=short)"
echo ""

read -p "Proceed with cluster initialization? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cluster initialization cancelled."
    exit 1
fi

# Initialize the cluster
echo "Initializing Kubernetes cluster..."
kubeadm init \
    --apiserver-advertise-address="$CONTROL_PLANE_IP" \
    --pod-network-cidr="$POD_NETWORK_CIDR" \
    --kubernetes-version="$(kubeadm version --output=short)" \
    --ignore-preflight-errors=NumCPU

# Configure kubectl for root user
echo "Configuring kubectl for root user..."
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

# Test kubectl access
echo "Testing kubectl access..."
if kubectl get nodes >/dev/null 2>&1; then
    echo "✓ kubectl is working correctly"
    kubectl get nodes
else
    echo "✗ kubectl test failed"
    exit 1
fi

# Install Calico CNI
echo ""
echo "Installing Calico CNI..."

# Install Calico operator and CRDs
echo "Installing Calico operator..."
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/tigera-operator.yaml

# Download and apply Calico custom resources
echo "Installing Calico custom resources..."
curl -LO https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/custom-resources.yaml
kubectl apply -f custom-resources.yaml

# Wait for Calico pods to be ready
echo "Waiting for Calico pods to be ready..."
echo "This may take a few minutes..."

# Monitor Calico installation
kubectl wait --for=condition=Available --timeout=300s deployment/calico-kube-controllers -n calico-system
kubectl wait --for=condition=Ready --timeout=300s pod -l k8s-app=calico-node -n calico-system

echo "✓ Calico installation completed"

# Display cluster status
echo ""
echo "=== Cluster initialization completed! ==="
echo ""
kubectl get nodes -o wide
kubectl get pods -n calico-system

# Extract and display join command
echo ""
echo "=== Worker Node Join Command ==="
echo "Run the following command on each worker node:"
echo ""
kubeadm token create --print-join-command
echo ""

# Configure kubectl for non-root users
echo "To configure kubectl for non-root users, run:"
echo ""
echo "  mkdir -p \$HOME/.kube"
echo "  sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config"
echo "  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
echo ""

# Save kubeconfig for later use
cp /etc/kubernetes/admin.conf /root/kubeconfig-backup
echo "✓ Kubeconfig backed up to /root/kubeconfig-backup"

echo ""
echo "Next steps:"
echo "1. Run the join command on all worker nodes"
echo "2. Verify all nodes are Ready: kubectl get nodes"
echo "3. Deploy the inference stack using Helm charts"
