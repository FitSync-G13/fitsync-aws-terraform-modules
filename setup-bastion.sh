#!/bin/bash

# Bastion Setup Script for K3s Management
# Run this script on the bastion host after SSH connection

set -e

echo "=== Setting up bastion for K3s management ==="

# Update system packages
echo "Updating system packages..."
sudo apt-get update

# Install kubectl (latest stable)
echo "Installing latest kubectl..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Install helm (latest)
echo "Installing latest Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Cilium CLI (latest)
echo "Installing latest Cilium CLI..."
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ $(uname -m) = aarch64 ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# Install istioctl (latest)
echo "Installing latest istioctl..."
cd /tmp
curl -L https://istio.io/downloadIstio | sh -
ISTIO_DIR=$(ls -d istio-* 2>/dev/null | head -1)
if [ -n "$ISTIO_DIR" ]; then
  sudo cp ${ISTIO_DIR}/bin/istioctl /usr/local/bin/
  rm -rf ${ISTIO_DIR}
else
  echo "Warning: Could not find Istio directory"
fi
cd -

# Install k9s (latest Kubernetes CLI UI)
echo "Installing latest k9s..."
K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
curl -L -o k9s.tar.gz "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz"
tar -xzf k9s.tar.gz k9s
sudo install -o root -g root -m 0755 k9s /usr/local/bin/k9s
rm k9s k9s.tar.gz

# Install kubectx and kubens (latest)
echo "Installing latest kubectx and kubens..."
KUBECTX_VERSION=$(curl -s https://api.github.com/repos/ahmetb/kubectx/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
curl -L -o kubectx.tar.gz "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubectx_${KUBECTX_VERSION}_linux_x86_64.tar.gz"
curl -L -o kubens.tar.gz "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubens_${KUBECTX_VERSION}_linux_x86_64.tar.gz"
tar -xzf kubectx.tar.gz kubectx
tar -xzf kubens.tar.gz kubens
sudo install -o root -g root -m 0755 kubectx /usr/local/bin/kubectx
sudo install -o root -g root -m 0755 kubens /usr/local/bin/kubens
rm kubectx kubens kubectx.tar.gz kubens.tar.gz

# Install stern (latest log viewer)
echo "Installing latest stern..."
STERN_VERSION=$(curl -s https://api.github.com/repos/stern/stern/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
curl -L -o stern.tar.gz "https://github.com/stern/stern/releases/download/${STERN_VERSION}/stern_${STERN_VERSION#v}_linux_amd64.tar.gz"
tar -xzf stern.tar.gz stern
sudo install -o root -g root -m 0755 stern /usr/local/bin/stern
rm stern stern.tar.gz

# Setup bash completions and aliases
echo "Setting up bash completions and aliases..."
{
    echo ''
    echo '# Kubernetes tools completions and aliases'
    echo 'source <(kubectl completion bash)'
    echo 'source <(helm completion bash)'
    echo 'complete -F __start_kubectl k'
    echo 'alias k=kubectl'
    echo 'alias kgp="kubectl get pods"'
    echo 'alias kgs="kubectl get svc"'
    echo 'alias kgn="kubectl get nodes"'
    echo 'alias kd="kubectl describe"'
    echo 'alias kl="kubectl logs"'
    echo 'alias kex="kubectl exec -it"'
    echo 'alias ctx="kubectx"'
    echo 'alias ns="kubens"'
} >> ~/.bashrc

# Create .kube directory
mkdir -p ~/.kube

echo "=== All tools installed successfully ==="
echo "kubectl version: $(kubectl version --client --short 2>/dev/null || echo 'Not configured')"
echo "helm version: $(helm version --short)"
echo "cilium version: $(cilium version --client)"
echo "istioctl version: $(istioctl version --remote=false)"
echo "k9s version: $(k9s version --short)"
echo "kubectx version: $(kubectx --version)"
echo "stern version: $(stern --version)"

echo ""
echo "=== Next steps ==="
echo "1. Get kubeconfig from K3s master:"
echo "   ssh -F ../ssh-config master1 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config"
echo ""
echo "2. Update server URL in kubeconfig:"
echo "   sed -i 's|server: https://127.0.0.1:6443|server: https://LOAD_BALANCER_DNS:6443|g' ~/.kube/config"
echo "   (Replace LOAD_BALANCER_DNS with your actual K3s API load balancer DNS)"
echo ""
echo "3. Test connection:"
echo "   kubectl get nodes"
echo ""
echo "4. Reload bash to get completions:"
echo "   source ~/.bashrc"
echo ""
echo "=== Useful commands ==="
echo "k get nodes                          # List cluster nodes"
echo "kgp -A                               # List all pods"
echo "kgs -A                               # List all services"
echo "cilium status                        # Check Cilium status"
echo "istioctl version                     # Check Istio version"
echo "istioctl proxy-status                # Check Istio proxy status"
echo "k get pods -n istio-system           # List Istio pods"
echo "helm list -A                         # List Helm releases"
echo "k9s                                  # Launch K9s UI"
echo "ctx                                  # Switch contexts"
echo "ns default                           # Switch to default namespace"
echo "stern app-name                       # Stream logs for app"
