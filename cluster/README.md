# Kubernetes Cluster Setup on RHEL

This directory contains scripts to bootstrap a Kubernetes cluster on RHEL bare metal nodes using kubeadm.

## Architecture

- **Container Runtime**: containerd with systemd cgroups
- **CNI**: Calico (operator-based installation)
- **Cluster Management**: kubeadm
- **Kubernetes Version**: v1.33

## Prerequisites

- 3 RHEL bare metal nodes with network connectivity
- Root access or sudo privileges on all nodes
- At least 2 CPUs and 2GB RAM per node
- Unique hostnames for each node

## Installation Order

### 1. Prepare All Nodes

Run these scripts on **every node** (control-plane and workers):

```bash
# Set hostnames, configure networking, disable swap
sudo ./scripts/00-rhel-prereqs.sh

# Install containerd with systemd cgroups
sudo ./scripts/01-install-containerd.sh

# Install kubeadm, kubelet, kubectl
sudo ./scripts/02-install-kubeadm.sh
```

### 2. Initialize Control Plane

Run this script **only on the control-plane node**:

```bash
# Initialize cluster and install Calico CNI
sudo ./scripts/10-controlplane-init.sh
```

This script will:
- Initialize the Kubernetes control plane
- Install and configure Calico CNI
- Display the worker join command
- Configure kubectl for the root user

### 3. Join Worker Nodes

Run this script on **each worker node**:

```bash
# Join worker to the cluster
sudo ./scripts/11-worker-join.sh
```

You'll need the join command from step 2.

## Script Details

### 00-rhel-prereqs.sh
- Sets hostname and updates `/etc/hosts`
- Disables swap (Kubernetes requirement)
- Loads kernel modules for container networking
- Configures sysctl parameters
- Sets up firewall rules for Kubernetes
- Updates system packages

### 01-install-containerd.sh
- Adds Docker repository
- Installs containerd
- Configures systemd cgroups (required for Kubernetes)
- Enables and starts containerd service

### 02-install-kubeadm.sh
- Adds Kubernetes repository (v1.33)
- Installs kubelet, kubeadm, kubectl
- Configures kubelet for systemd cgroups
- Optionally pre-pulls Kubernetes images

### 10-controlplane-init.sh
- Initializes Kubernetes control plane
- Configures kubectl for root user
- Installs Calico CNI operator and custom resources
- Displays worker join command
- Backs up kubeconfig

### 11-worker-join.sh
- Prompts for join command from control plane
- Executes kubeadm join
- Verifies kubelet is running
- Provides troubleshooting guidance

## Network Configuration

### Pod Network
- CIDR: `192.168.0.0/16` (Calico default)
- CNI: Calico with operator-based installation

### Firewall Ports

**Control Plane:**
- 6443/tcp: Kubernetes API server
- 2379-2380/tcp: etcd server client API
- 10250/tcp: Kubelet API
- 10259/tcp: kube-scheduler
- 10257/tcp: kube-controller-manager

**All Nodes:**
- 10250/tcp: Kubelet API
- 30000-32767/tcp: NodePort Services
- 179/tcp: Calico BGP

## Verification

After setup, verify the cluster:

```bash
# Check nodes
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system

# Check Calico
kubectl get pods -n calico-system

# Test pod networking
kubectl run test-pod --image=nginx --port=80
kubectl get pod test-pod -o wide
```

## Troubleshooting

### Common Issues

1. **kubelet fails to start**
   ```bash
   journalctl -xeu kubelet
   systemctl status kubelet
   ```

2. **Pods stuck in Pending**
   ```bash
   kubectl describe pod <pod-name>
   kubectl get events --sort-by=.metadata.creationTimestamp
   ```

3. **Network connectivity issues**
   ```bash
   # Check Calico
   kubectl get pods -n calico-system
   
   # Check node network
   ip route
   iptables -L -n
   ```

4. **Join command expired**
   ```bash
   # Generate new token on control plane
   kubeadm token create --print-join-command
   ```

### Log Locations

- kubelet: `journalctl -u kubelet`
- containerd: `journalctl -u containerd`
- Kubernetes events: `kubectl get events --all-namespaces`

## Security Notes

- SELinux is set to permissive mode for Kubernetes compatibility
- Firewall rules are configured for cluster communication
- Consider implementing NetworkPolicies after cluster setup
- Rotate tokens regularly in production environments

## Next Steps

After cluster setup:
1. Deploy MetalLB for LoadBalancer services
2. Install ingress-nginx for HTTP/HTTPS routing
3. Set up monitoring with metrics-server
4. Deploy the inference stack components

## Cleanup

To reset a node (removes it from cluster):

```bash
# On worker nodes
sudo kubeadm reset
sudo systemctl stop kubelet containerd
sudo rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd

# On control plane (destroys entire cluster)
sudo kubeadm reset
sudo systemctl stop kubelet containerd
sudo rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd
```
