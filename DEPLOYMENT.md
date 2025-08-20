# Deployment Guide - Inference Stack

This guide provides step-by-step instructions to deploy the complete inference stack on your RHEL bare metal nodes.

## Prerequisites Checklist

- [ ] 3 RHEL bare metal nodes with network connectivity
- [ ] Root access on all nodes
- [ ] Minimum 2 CPUs and 4GB RAM per node
- [ ] At least 50GB storage per node
- [ ] Unique hostnames configured
- [ ] Network connectivity between all nodes

## Phase 1: Cluster Setup (30-45 minutes)

### Step 1: Update Configuration Files

Before starting, update these configuration values for your environment:

1. **IP Addresses in MetalLB** (`env/metallb-values.yaml`):
   ```yaml
   addresses:
     - "10.0.0.240-10.0.0.250"  # CHANGE to your available IP range
   ```

2. **Node Hostnames in Ollama configs**:
   - `env/ollama-llama31-values.yaml`: Update `kubernetes.io/hostname: k8s-w-1`
   - `env/ollama-mistral-values.yaml`: Update `kubernetes.io/hostname: k8s-w-2`
   - `env/ollama-phi3-values.yaml`: Update `kubernetes.io/hostname: k8s-cp-1`

3. **Domain Names** (`env/openwebui-values.yaml`):
   ```yaml
   hosts:
     - host: inference.local  # CHANGE to your domain
   ```

4. **Security Keys** (IMPORTANT - Change all of these):
   - `env/postgres-values.yaml`: Change `password: "litellm123"`
   - `env/redis-values.yaml`: Change `password: "redispass"`
   - `env/litellm-values.yaml`: Change `sk-admin-REPLACE` and `sk-salt-REPLACE`
   - `env/openwebui-values.yaml`: Change `WEBUI_SECRET_KEY`

### Step 2: Prepare All Nodes (Run on ALL 3 nodes)

```bash
# On each node (control-plane and workers)
sudo ./cluster/scripts/00-rhel-prereqs.sh
sudo ./cluster/scripts/01-install-containerd.sh
sudo ./cluster/scripts/02-install-kubeadm.sh
```

### Step 3: Initialize Control Plane (Run on control-plane only)

```bash
# On control-plane node only
sudo ./cluster/scripts/10-controlplane-init.sh
```

**Save the join command** that appears at the end!

### Step 4: Join Worker Nodes (Run on each worker)

```bash
# On each worker node
sudo ./cluster/scripts/11-worker-join.sh
# Paste the join command when prompted
```

### Step 5: Verify Cluster

```bash
# On control-plane node
kubectl get nodes -o wide
kubectl get pods -n kube-system
kubectl get pods -n calico-system
```

All nodes should show `Ready` status.

## Phase 2: Infrastructure Deployment (15-20 minutes)

### Step 1: Add Helm Repositories

```bash
helm repo add metallb https://metallb.github.io/metallb
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server
helm repo update
```

### Step 2: Deploy Core Infrastructure

```bash
# MetalLB for LoadBalancer services
helm upgrade --install metallb metallb/metallb \
  -n metallb-system --create-namespace \
  -f env/metallb-values.yaml

# Configure MetalLB address pool (adjust IP range in the command)
kubectl apply -f - <<'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata: {name: default, namespace: metallb-system}
spec: {addresses: ["10.0.0.240-10.0.0.250"]}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata: {name: l2, namespace: metallb-system}
spec: {ipAddressPools: ["default"]}
EOF

# Ingress NGINX
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f env/ingress-nginx-values.yaml

# Metrics Server
helm upgrade --install metrics-server metrics-server/metrics-server \
  -n kube-system
```

### Step 3: Deploy Platform Services

```bash
# PostgreSQL
helm upgrade --install pg bitnami/postgresql \
  -n platform --create-namespace \
  -f env/postgres-values.yaml

# Redis
helm upgrade --install redis bitnami/redis \
  -n platform \
  -f env/redis-values.yaml

# Wait for databases to be ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=postgresql -n platform --timeout=300s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=redis -n platform --timeout=300s
```

## Phase 3: Model Deployment (20-30 minutes)

### Step 1: Deploy Ollama Instances

```bash
helm repo add cowboysysop https://cowboysysop.github.io/charts/
helm repo update

# Deploy Llama 3.1 (worker node 1)
helm upgrade --install ollama-llama31 cowboysysop/ollama \
  -n models --create-namespace \
  -f env/ollama-llama31-values.yaml

# Deploy Mistral (worker node 2)
helm upgrade --install ollama-mistral cowboysysop/ollama \
  -n models \
  -f env/ollama-mistral-values.yaml

# Deploy Phi3 Mini (control plane - demo only)
helm upgrade --install ollama-phi3 cowboysysop/ollama \
  -n models \
  -f env/ollama-phi3-values.yaml
```

### Step 2: Monitor Model Loading

```bash
# Watch pods starting up
kubectl get pods -n models -w

# Check individual model logs (in separate terminals)
kubectl logs -n models -f deploy/ollama-llama31
kubectl logs -n models -f deploy/ollama-mistral  
kubectl logs -n models -f deploy/ollama-phi3
```

**Note**: Model downloads can take 10-30 minutes depending on your internet connection.

## Phase 4: Router and UI Deployment (10-15 minutes)

### Step 1: Deploy LiteLLM Router

```bash
# Download LiteLLM Helm chart
helm pull oci://ghcr.io/berriai/litellm-helm --version 0.1.2
tar -xzf litellm-helm-0.1.2.tgz -C charts/

# Deploy LiteLLM
helm upgrade --install litellm ./charts/litellm-helm \
  -n router --create-namespace \
  -f env/litellm-values.yaml
```

### Step 2: Deploy Open WebUI

```bash
helm repo add open-webui https://helm.openwebui.com/
helm repo update

helm upgrade --install webui open-webui/open-webui \
  -n ui --create-namespace \
  -f env/openwebui-values.yaml
```

## Phase 5: Testing and Verification (10 minutes)

### Step 1: Check All Services

```bash
# Check all deployments
kubectl get pods --all-namespaces

# Check services and external IPs
kubectl get svc --all-namespaces | grep LoadBalancer

# Check ingress
kubectl get ingress --all-namespaces
```

### Step 2: Test LiteLLM API

```bash
# Port forward to LiteLLM
kubectl -n router port-forward svc/litellm 4000:4000 &

# Test Llama 3.1
curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H 'Authorization: Bearer sk-admin-REPLACE' \
  -H 'Content-Type: application/json' \
  -d '{"model":"llama31-local","messages":[{"role":"user","content":"Hello from Llama!"}]}' | jq -r '.choices[0].message.content'

# Test Mistral
curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H 'Authorization: Bearer sk-admin-REPLACE' \
  -H 'Content-Type: application/json' \
  -d '{"model":"mistral-local","messages":[{"role":"user","content":"Hello from Mistral!"}]}' | jq -r '.choices[0].message.content'

# Test Phi3
curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H 'Authorization: Bearer sk-admin-REPLACE' \
  -H 'Content-Type: application/json' \
  -d '{"model":"phi3-mini-local","messages":[{"role":"user","content":"Hello from Phi3!"}]}' | jq -r '.choices[0].message.content'
```

### Step 3: Access Web UI

1. Get the LoadBalancer IP:
   ```bash
   kubectl get svc -n ui webui
   ```

2. Open browser to the external IP or configured domain

3. Sign up and start chatting with different models!

## Post-Deployment Configuration

### 1. Create API Keys in LiteLLM

```bash
# Create a virtual key for customers
curl -X POST http://127.0.0.1:4000/key/generate \
  -H 'Authorization: Bearer sk-admin-REPLACE' \
  -H 'Content-Type: application/json' \
  -d '{
    "models": ["llama31-local", "mistral-local", "phi3-mini-local"],
    "max_budget": 100,
    "duration": "30d"
  }'
```

### 2. Enable Auto-scaling

```bash
# Enable HPA for LiteLLM
kubectl autoscale deployment litellm -n router \
  --cpu-percent=70 --min=2 --max=10

# Enable HPA for Open WebUI
kubectl autoscale deployment webui -n ui \
  --cpu-percent=70 --min=1 --max=5
```

### 3. Monitor Resource Usage

```bash
# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods --all-namespaces

# Check model backend distribution
kubectl get pods -n models -o wide
```

## Troubleshooting Common Issues

### Models Not Loading
```bash
# Check Ollama logs
kubectl logs -n models deploy/ollama-llama31
kubectl describe pod -n models -l app=ollama-llama31

# Check disk space
kubectl exec -n models deploy/ollama-llama31 -- df -h
```

### LiteLLM Connection Errors
```bash
# Check LiteLLM logs
kubectl logs -n router deploy/litellm

# Test database connectivity
kubectl exec -n platform deploy/pg-postgresql -- pg_isready
```

### LoadBalancer Not Getting External IP
```bash
# Check MetalLB
kubectl get pods -n metallb-system
kubectl logs -n metallb-system deploy/metallb-controller

# Check address pool
kubectl get ipaddresspool -n metallb-system
```

## Next Steps

1. **Security**: Configure TLS certificates with cert-manager
2. **Monitoring**: Deploy Prometheus and Grafana
3. **GPU Support**: Update Ollama configurations for GPU nodes
4. **Backup**: Set up regular backups for PostgreSQL and model data
5. **Production**: Review and update all default passwords

## Deployment Timeline

- **Phase 1 (Cluster)**: 30-45 minutes
- **Phase 2 (Infrastructure)**: 15-20 minutes  
- **Phase 3 (Models)**: 20-30 minutes (depends on internet speed)
- **Phase 4 (Router/UI)**: 10-15 minutes
- **Phase 5 (Testing)**: 10 minutes

**Total**: ~85-120 minutes for complete deployment

## Support

- Check logs: `kubectl logs -n <namespace> <pod-name>`
- Get events: `kubectl get events --sort-by=.metadata.creationTimestamp`
- Describe resources: `kubectl describe <resource> <name> -n <namespace>`

Happy inferencing! 🚀
