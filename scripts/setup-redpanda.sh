#!/bin/bash

# Setup Redpanda Cluster Script
# This script deploys Redpanda on local Kubernetes using Helm

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if environment variables are loaded
if [ -z "$NAMESPACE" ]; then
    print_error "Environment variables not loaded. Please source .env file first."
    exit 1
fi

print_status "Setting up Redpanda cluster in namespace: $NAMESPACE"

# Add Redpanda Helm repository if not already added
if ! helm repo list | grep -q "redpanda"; then
    print_status "Adding Redpanda Helm repository..."
    helm repo add redpanda https://charts.redpanda.com
    helm repo update
    print_success "Redpanda Helm repository added"
else
    print_status "Redpanda Helm repository already exists"
fi

# Create namespace if it doesn't exist
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    print_status "Creating namespace: $NAMESPACE"
    kubectl apply -f k8s/redpanda/namespace.yaml
    print_success "Namespace created"
else
    print_status "Namespace $NAMESPACE already exists"
fi

# Deploy Redpanda using Helm
print_status "Deploying Redpanda cluster..."
helm upgrade --install redpanda redpanda/redpanda \
    --namespace "$NAMESPACE" \
    --values k8s/redpanda/values.yaml \
    --set cluster.replicas="$REDPANDA_REPLICAS" \
    --wait \
    --debug \
    --timeout 40m

print_success "Redpanda cluster deployment initiated"

# Wait for Redpanda pods to be ready
print_status "Waiting for Redpanda pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=redpanda-statefulset -n "$NAMESPACE" --timeout=300s

print_success "Redpanda pods are ready"

# Verify Redpanda cluster status
print_status "Verifying Redpanda cluster status..."
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redpanda

# Check Redpanda cluster health
print_status "Checking Redpanda cluster health..."
kubectl exec -n "$NAMESPACE" redpanda-0 -- rpk cluster health

print_success "Redpanda cluster setup completed successfully"

# Display connection information
print_status "Redpanda cluster connection information:"
echo "  - Kafka API: localhost:30092"
echo "  - Admin API: localhost:30964"
echo "  - Proxy API: localhost:30082"
echo "  - Schema Registry: localhost:30081"
echo ""
echo "  - Internal Kafka API: redpanda-0.redpanda.$NAMESPACE.svc.cluster.local:9092"
echo "  - Internal Admin API: redpanda-0.redpanda.$NAMESPACE.svc.cluster.local:9644" 