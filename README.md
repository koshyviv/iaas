# Inference Stack - Kubernetes LLM Infrastructure

A production-ready Kubernetes-based LLM inference platform designed for bare metal RHEL nodes. This stack provides:

* **Kubernetes cluster** (1 control-plane + 2 workers) with kubeadm + Calico CNI
* **L4/L7 routing** on bare metal with MetalLB + ingress-nginx
* **Per-model backends** (Ollama pods, one per node) with intelligent routing
* **LiteLLM proxy** for OpenAI-compatible API with keys/usage tracking
* **Simple chat UI** (Open WebUI) for end users
* **Autoscaling primitives** and basic observability

## Architecture Overview

* **Kubernetes:** kubeadm + containerd; **CNI:** Calico; **LB:** MetalLB; **Ingress:** ingress-nginx
* **Router:** LiteLLM proxy (OpenAI-compatible), with PostgreSQL (keys/usage) + Redis (caching)
* **Model backends:** Ollama pods (1 model per node); CPU-first, GPU-ready
* **UI:** Open WebUI (talks to LiteLLM via OpenAI API)
* **Observability:** metrics-server (kubectl top / HPA)

## Quick Start

### Prerequisites
- 3 RHEL bare metal nodes with network connectivity
- Root access or sudo privileges on all nodes
- Basic networking setup (hostnames, /etc/hosts)

### Deployment Steps

1. **Prepare all nodes**: Run cluster preparation scripts on every node
2. **Initialize cluster**: Set up Kubernetes control plane
3. **Join workers**: Add worker nodes to the cluster
4. **Deploy infrastructure**: Install MetalLB, ingress-nginx, and platform services
5. **Deploy models**: Set up Ollama instances with different models per node
6. **Configure routing**: Deploy LiteLLM proxy for intelligent model routing
7. **Launch UI**: Deploy Open WebUI for end-user access

### Repository Structure

```
inference-stack/
├─ cluster/                  # kubeadm + node bootstrap
│  ├─ scripts/
│  │  ├─ 00-rhel-prereqs.sh
│  │  ├─ 01-install-containerd.sh
│  │  ├─ 02-install-kubeadm.sh
│  │  ├─ 10-controlplane-init.sh
│  │  └─ 11-worker-join.sh
│  └─ README.md
├─ charts/
│  └─ inference-stack/      # umbrella helm chart
│     ├─ Chart.yaml
│     ├─ values.yaml
│     └─ templates/         # small glue (Ingress, Secrets, ConfigMaps)
├─ env/
│  ├─ metallb-values.yaml
│  ├─ ingress-nginx-values.yaml
│  ├─ litellm-values.yaml
│  ├─ postgres-values.yaml
│  ├─ redis-values.yaml
│  ├─ openwebui-values.yaml
│  ├─ ollama-llama31-values.yaml
│  ├─ ollama-mistral-values.yaml
│  └─ ollama-phi3-values.yaml
└─ README.md
```

## Detailed Setup Instructions

### 1. Node Preparation (All Nodes)

Run the cluster preparation scripts on every node:

```bash
# Set appropriate hostnames and update /etc/hosts
sudo ./cluster/scripts/00-rhel-prereqs.sh

# Install containerd with systemd cgroups
sudo ./cluster/scripts/01-install-containerd.sh

# Install kubeadm, kubelet, kubectl
sudo ./cluster/scripts/02-install-kubeadm.sh
```

### 2. Cluster Initialization (Control Plane Only)

```bash
# Initialize the control plane
sudo ./cluster/scripts/10-controlplane-init.sh

# Install Calico CNI
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/tigera-operator.yaml
curl -LO https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/custom-resources.yaml
kubectl apply -f custom-resources.yaml
```

### 3. Worker Node Setup

Use the join command from the control plane initialization:

```bash
# Run on each worker node
sudo kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

### 4. Infrastructure Deployment

Deploy the core infrastructure components:

```bash
# MetalLB for LoadBalancer services
helm repo add metallb https://metallb.github.io/metallb
helm upgrade --install metallb metallb/metallb -n metallb-system --create-namespace

# Configure MetalLB address pool (adjust IP range)
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
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer
```

### 5. Platform Services

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server
helm repo update

# PostgreSQL for LiteLLM
helm upgrade --install pg bitnami/postgresql -n platform --create-namespace \
  --values env/postgres-values.yaml

# Redis for caching
helm upgrade --install redis bitnami/redis -n platform --values env/redis-values.yaml

# Metrics server
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system
```

### 6. Model Deployment

Deploy Ollama instances with different models:

```bash
helm repo add cowboysysop https://cowboysysop.github.io/charts/

# Deploy models to different nodes
helm upgrade --install ollama-llama31 cowboysysop/ollama -n models --create-namespace -f env/ollama-llama31-values.yaml
helm upgrade --install ollama-mistral cowboysysop/ollama -n models -f env/ollama-mistral-values.yaml
helm upgrade --install ollama-phi3 cowboysysop/ollama -n models -f env/ollama-phi3-values.yaml
```

### 7. LiteLLM Router

```bash
# Pull LiteLLM Helm chart
helm pull oci://ghcr.io/berriai/litellm-helm --version 0.1.2
tar -xzf litellm-helm-0.1.2.tgz -C charts/

# Deploy LiteLLM proxy
helm upgrade --install litellm ./charts/litellm-helm -n router --create-namespace -f env/litellm-values.yaml
```

### 8. Web UI

```bash
helm repo add open-webui https://helm.openwebui.com/
helm upgrade --install webui open-webui/open-webui -n ui --create-namespace -f env/openwebui-values.yaml
```

### 9. Testing

```bash
# Port forward to test LiteLLM
kubectl -n router port-forward svc/litellm 4000:4000 &

# Test different models
curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H 'Authorization: Bearer sk-admin-REPLACE' \
  -H 'Content-Type: application/json' \
  -d '{"model":"llama31-local","messages":[{"role":"user","content":"Hello from Llama!"}]}'
```

## Configuration

All component configurations are in the `env/` directory. Key files:

- `metallb-values.yaml` - LoadBalancer IP pool configuration
- `litellm-values.yaml` - Router configuration with model endpoints
- `ollama-*-values.yaml` - Model-specific deployments with node affinity
- `postgres-values.yaml` / `redis-values.yaml` - Database configurations
- `openwebui-values.yaml` - UI configuration

## Customization

### Adding New Models

1. Create new Ollama values file in `env/`
2. Deploy with Helm: `helm upgrade --install ollama-<model> cowboysysop/ollama -f env/ollama-<model>-values.yaml`
3. Update `litellm-values.yaml` to include the new model endpoint
4. Redeploy LiteLLM: `helm upgrade litellm ./charts/litellm-helm -f env/litellm-values.yaml`

### GPU Support

Update Ollama values files to include GPU resources and node selectors for GPU nodes.

### TLS/HTTPS

Add cert-manager and configure Ingress with TLS certificates.

### Advanced Observability

Deploy kube-prometheus-stack for comprehensive monitoring and alerting.

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending**: Check node resources and storage
2. **MetalLB not assigning IPs**: Verify IP pool configuration and network setup
3. **Models not loading**: Check Ollama logs and ensure sufficient disk space
4. **LiteLLM connection errors**: Verify service DNS names and network policies

### Useful Commands

```bash
# Check cluster status
kubectl get nodes -o wide
kubectl get pods --all-namespaces

# Check services and ingress
kubectl get svc,ingress --all-namespaces

# View logs
kubectl logs -n <namespace> <pod-name>

# Resource usage
kubectl top nodes
kubectl top pods --all-namespaces
```

## License

This project is provided as-is for educational and production use. Individual components maintain their respective licenses.