#!/bin/bash
set -euo pipefail

# Join worker node to Kubernetes cluster
# Run this script on worker nodes AFTER control plane is initialized

echo "=== Joining Worker Node to Kubernetes Cluster ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (or with sudo)" 
   exit 1
fi

# Check if node is already part of a cluster
if systemctl is-active kubelet >/dev/null 2>&1; then
    echo "WARNING: kubelet is already running. This node may already be part of a cluster."
    echo "Current kubelet status:"
    systemctl status kubelet --no-pager -l || true
    echo ""
    read -p "Continue anyway? This may cause issues (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Worker join cancelled."
        exit 1
    fi
fi

echo ""
echo "To join this worker node to the cluster, you need the join command"
echo "from the control plane initialization output."
echo ""
echo "The command should look like:"
echo "kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
echo ""

# Option 1: Paste the join command
echo "Option 1: Paste the complete join command"
read -p "Enter the complete kubeadm join command: " JOIN_COMMAND

if [[ -z "$JOIN_COMMAND" ]]; then
    echo "No join command provided. Exiting."
    exit 1
fi

# Validate the join command format
if [[ ! "$JOIN_COMMAND" =~ ^kubeadm\ join.* ]]; then
    echo "ERROR: Invalid join command format. It should start with 'kubeadm join'"
    exit 1
fi

echo ""
echo "Join command to execute:"
echo "$JOIN_COMMAND"
echo ""

read -p "Execute this join command? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Worker join cancelled."
    exit 1
fi

# Execute the join command
echo "Joining cluster..."
eval "$JOIN_COMMAND"

# Verify the join was successful
echo ""
echo "Verifying worker node join..."

# Wait a moment for kubelet to start
sleep 10

# Check kubelet status
if systemctl is-active kubelet >/dev/null 2>&1; then
    echo "✓ kubelet is running"
    systemctl status kubelet --no-pager -l
else
    echo "✗ kubelet is not running"
    echo "Join may have failed. Check logs:"
    echo "  journalctl -xeu kubelet"
    exit 1
fi

# Check if node appears in cluster (requires kubectl on control plane)
echo ""
echo "=== Worker node join completed! ==="
echo ""
echo "To verify the node has joined successfully, run on the control plane:"
echo "  kubectl get nodes"
echo ""
echo "The node should appear with status 'Ready' after a few minutes."
echo ""
echo "To troubleshoot issues:"
echo "  - Check kubelet logs: journalctl -xeu kubelet"
echo "  - Check kubelet status: systemctl status kubelet"
echo "  - Verify network connectivity to control plane"
echo ""

# Display local node info
echo "Local node information:"
echo "Hostname: $(hostname)"
echo "IP Address: $(hostname -I | awk '{print $1}')"
echo "Kubelet status: $(systemctl is-active kubelet)"
