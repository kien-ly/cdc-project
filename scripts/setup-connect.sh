#!/bin/bash

# Setup Kafka Connect Script
# This script deploys Kafka Connect with Debezium and S3 connectors

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

print_status "Setting up Kafka Connect in namespace: $NAMESPACE"

# Create the namespace if it doesn't exist
print_status "Ensuring namespace '$NAMESPACE' exists..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create Kubernetes secrets for sensitive data
print_status "Creating Kubernetes secrets..."

# AWS Credentials Secret
kubectl create secret generic aws-credentials \
    --namespace "$NAMESPACE" \
    --from-literal=aws-region="$AWS_REGION" \
    --from-literal=aws-access-key-id="$AWS_ACCESS_KEY_ID" \
    --from-literal=aws-secret-access-key="$AWS_SECRET_ACCESS_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -

# RDS Credentials Secret
kubectl create secret generic rds-credentials \
    --namespace "$NAMESPACE" \
    --from-literal=aws-rds-endpoint="$AWS_RDS_ENDPOINT" \
    --from-literal=aws-rds-dbname="$AWS_RDS_DBNAME" \
    --from-literal=aws-rds-user="$AWS_RDS_USER" \
    --from-literal=aws-rds-password="$AWS_RDS_PASSWORD" \
    --from-literal=aws-rds-port="$AWS_RDS_PORT" \
    --dry-run=client -o yaml | kubectl apply -f -

# S3 Configuration Secret
kubectl create secret generic s3-config \
    --namespace "$NAMESPACE" \
    --from-literal=s3-bucket-name="$S3_BUCKET_NAME" \
    --dry-run=client -o yaml | kubectl apply -f -

print_success "Kubernetes secrets created"

# Update ConfigMap with current values
print_status "Updating ConfigMap with current configuration..."
kubectl create configmap cdc-config \
    --namespace "$NAMESPACE" \
    --from-literal=postgres-schema-to-track="$POSTGRES_SCHEMA_TO_TRACK" \
    --from-literal=postgres-table-to-track="$POSTGRES_TABLE_TO_TRACK" \
    --from-literal=replication-slot-name="$REPLICATION_SLOT_NAME" \
    --from-literal=debezium-connector-version="$DEBEZIUM_CONNECTOR_VERSION" \
    --from-literal=s3-sink-connector-version="$S3_SINK_CONNECTOR_VERSION" \
    --dry-run=client -o yaml | kubectl apply -f -

print_success "ConfigMap updated"

# Deploy Kafka Connect
print_status "Deploying Kafka Connect..."
kubectl apply -f k8s/kafka-connect/deployment.yaml
kubectl apply -f k8s/kafka-connect/service.yaml

print_success "Kafka Connect deployment initiated"

# Wait for Kafka Connect pod to be ready
print_status "Waiting for Kafka Connect pod to be ready..."
print_status "Checking pod status every 10 seconds..."

# Wait for pod to be running
while true; do
    POD_STATUS=$(kubectl get pods -l app=kafka-connect -n "$NAMESPACE" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$POD_STATUS" = "Running" ]; then
        print_success "Pod is Running"
        break
    elif [ "$POD_STATUS" = "Pending" ]; then
        print_status "Pod is still Pending... waiting 10 seconds"
        sleep 10
    elif [ "$POD_STATUS" = "Failed" ]; then
        print_error "Pod failed to start"
        kubectl describe pod -l app=kafka-connect -n "$NAMESPACE"
        kubectl logs -l app=kafka-connect -n "$NAMESPACE" --tail=20
        exit 1
    elif [ "$POD_STATUS" = "NOT_FOUND" ]; then
        print_status "Pod not found yet... waiting 10 seconds"
        sleep 10
    else
        print_status "Pod status: $POD_STATUS... waiting 10 seconds"
        sleep 10
    fi
done

# Wait for containers to be ready
print_status "Waiting for containers to be ready..."
while true; do
    READY_STATUS=$(kubectl get pods -l app=kafka-connect -n "$NAMESPACE" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    
    if [ "$READY_STATUS" = "true" ]; then
        print_success "Containers are ready"
        break
    else
        print_status "Containers not ready yet... checking logs and waiting 10 seconds"
        kubectl logs -l app=kafka-connect -n "$NAMESPACE" --tail=5 2>/dev/null || echo "No logs available yet"
        sleep 10
    fi
done

# Wait for REST API to be accessible
print_status "Waiting for Kafka Connect REST API to be accessible..."
while true; do
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=kafka-connect -o jsonpath='{.items[0].metadata.name}')
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- curl -s http://localhost:8083/ >/dev/null 2>&1; then
        print_success "REST API is accessible from inside pod"
        break
    else
        print_status "REST API not accessible yet... waiting 10 seconds"
        # Show recent logs for debugging
        kubectl logs "$POD_NAME" -n "$NAMESPACE" --tail=3 2>/dev/null || echo "No logs available yet"
        sleep 10
    fi
done

# Set up port forwarding for external access
print_status "Setting up port forwarding for external REST API access..."
kubectl port-forward -n "$NAMESPACE" svc/kafka-connect 8083:8083 >/dev/null 2>&1 &
PF_PID=$!
sleep 5

# Wait for external REST API access
print_status "Waiting for external REST API access..."
while true; do
    if curl -s http://localhost:8083/ >/dev/null 2>&1; then
        print_success "External REST API is accessible"
        break
    else
        print_status "External REST API not accessible yet... waiting 5 seconds"
        sleep 5
    fi
done

print_success "Kafka Connect pod is fully ready"

# Verify Kafka Connect deployment
print_status "Verifying Kafka Connect deployment..."
kubectl get pods -n "$NAMESPACE" -l app=kafka-connect

# Create Kafka Connect topics
print_status "Creating Kafka Connect internal topics..."
kubectl exec -n "$NAMESPACE" redpanda-0 -- rpk topic create connect-configs --partitions 1 --replicas 3 || true
kubectl exec -n "$NAMESPACE" redpanda-0 -- rpk topic create connect-offsets --partitions 25 --replicas 3 || true
kubectl exec -n "$NAMESPACE" redpanda-0 -- rpk topic create connect-status --partitions 5 --replicas 3 || true
kubectl exec -n "$NAMESPACE" redpanda-0 -- rpk topic create schema-changes.postgres --partitions 1 --replicas 3 || true

print_success "Kafka Connect internal topics created"

# Verify topics
print_status "Verifying Kafka Connect topics..."
kubectl exec -n "$NAMESPACE" redpanda-0 -- rpk topic list

print_success "Kafka Connect setup completed successfully"

# Display connection information
print_status "Kafka Connect connection information:"
echo "  - REST API: http://localhost:8083"
echo "  - Internal REST API: http://kafka-connect.$NAMESPACE.svc.cluster.local:8083" 