#!/bin/bash

# Verify CDC Deployment Script
# This script verifies the CDC deployment and tests the data flow

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

print_status "Verifying CDC deployment in namespace: $NAMESPACE"

# Check Kubernetes cluster status
print_status "Checking Kubernetes cluster status..."
kubectl cluster-info
kubectl get nodes

# Check namespace and resources
print_status "Checking namespace and resources..."
kubectl get all -n "$NAMESPACE"

# Check Redpanda cluster status
print_status "Checking Redpanda cluster status..."
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redpanda

# Check Redpanda cluster health
print_status "Checking Redpanda cluster health..."
kubectl exec -n "$NAMESPACE" redpanda-0 -- rpk cluster health

# Check Redpanda topics
print_status "Checking Redpanda topics..."
kubectl exec -n "$NAMESPACE" redpanda-0 -- rpk topic list

# Check Kafka Connect status
print_status "Checking Kafka Connect status..."
kubectl get pods -n "$NAMESPACE" -l app=kafka-connect

# Check Kafka Connect logs
print_status "Checking Kafka Connect logs..."
kubectl logs -n "$NAMESPACE" -l app=kafka-connect --tail=20

# Check Kafka Connect REST API
print_status "Checking Kafka Connect REST API..."
if curl -s http://localhost:8083/ >/dev/null 2>&1; then
    print_success "Kafka Connect REST API is accessible"
    
    # Get connector list
    print_status "Getting connector list..."
    curl -s http://localhost:8083/connectors | jq .
    
    # Check connector status if they exist
    if curl -s http://localhost:8083/connectors/debezium-postgres >/dev/null 2>&1; then
        print_status "Checking Debezium PostgreSQL connector status..."
        curl -s http://localhost:8083/connectors/debezium-postgres/status | jq .
    else
        print_warning "Debezium PostgreSQL connector not found"
    fi
    
    if curl -s http://localhost:8083/connectors/s3-sink >/dev/null 2>&1; then
        print_status "Checking S3 Sink connector status..."
        curl -s http://localhost:8083/connectors/s3-sink/status | jq .
    else
        print_warning "S3 Sink connector not found"
    fi
else
    print_error "Kafka Connect REST API is not accessible"
    print_status "Checking if port forwarding is active..."
    kubectl get svc -n "$NAMESPACE" kafka-connect
fi

# Check Kubernetes secrets
print_status "Checking Kubernetes secrets..."
kubectl get secrets -n "$NAMESPACE"

# Check ConfigMap
print_status "Checking ConfigMap..."
kubectl get configmap -n "$NAMESPACE" cdc-config -o yaml

# Test AWS connectivity (if AWS CLI is available)
if command -v aws &> /dev/null; then
    print_status "Testing AWS connectivity..."
    if aws sts get-caller-identity >/dev/null 2>&1; then
        print_success "AWS credentials are valid"
        
        # Test S3 bucket access
        print_status "Testing S3 bucket access..."
        if aws s3 ls "s3://$S3_BUCKET_NAME" >/dev/null 2>&1; then
            print_success "S3 bucket is accessible"
            
            # List S3 bucket contents
            print_status "Listing S3 bucket contents..."
            aws s3 ls "s3://$S3_BUCKET_NAME" --recursive | head -10
        else
            print_error "S3 bucket is not accessible"
        fi
    else
        print_error "AWS credentials are not valid"
    fi
else
    print_warning "AWS CLI not found, skipping AWS connectivity test"
fi

# Test RDS connectivity (if psql is available)
if command -v psql &> /dev/null; then
    print_status "Testing RDS connectivity..."
    if PGPASSWORD="$AWS_RDS_PASSWORD" psql -h "$AWS_RDS_ENDPOINT" -U "$AWS_RDS_USER" -d "$AWS_RDS_DBNAME" -c "SELECT 1;" >/dev/null 2>&1; then
        print_success "RDS PostgreSQL is accessible"
        
        # Check replication slot
        print_status "Checking replication slot..."
        PGPASSWORD="$AWS_RDS_PASSWORD" psql -h "$AWS_RDS_ENDPOINT" -U "$AWS_RDS_USER" -d "$AWS_RDS_DBNAME" -c "SELECT slot_name, plugin, slot_type FROM pg_replication_slots WHERE slot_name = '$REPLICATION_SLOT_NAME';"
    else
        print_error "RDS PostgreSQL is not accessible"
    fi
else
    print_warning "PostgreSQL client (psql) not found, skipping RDS connectivity test"
fi

# Display summary
print_status "CDC Deployment Verification Summary:"
echo "  - Namespace: $NAMESPACE"
echo "  - Redpanda Cluster: $(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=redpanda --no-headers | wc -l) pods"
echo "  - Kafka Connect: $(kubectl get pods -n "$NAMESPACE" -l app=kafka-connect --no-headers | wc -l) pods"
echo "  - Topics: $(kubectl exec -n "$NAMESPACE" redpanda-0 -- rpk topic list | wc -l)"
echo "  - Connectors: $(curl -s http://localhost:8083/connectors 2>/dev/null | jq length 2>/dev/null || echo 'N/A')"

print_success "CDC deployment verification completed" 