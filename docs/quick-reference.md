# Kafka Connect Quick Reference Guide

## Table of Contents

1. [Environment Setup](#environment-setup)
2. [Deployment Commands](#deployment-commands)
3. [Connector Management](#connector-management)
4. [Monitoring and Health Checks](#monitoring-and-health-checks)
5. [Troubleshooting Commands](#troubleshooting-commands)
6. [Data Validation](#data-validation)
7. [Performance Monitoring](#performance-monitoring)

## Environment Setup

### Load Environment Variables
```bash
# Copy and load environment template
cp env.template env.sh
source env.sh

# Verify environment
echo "Namespace: $NAMESPACE"
echo "AWS Region: $AWS_REGION"
echo "RDS Endpoint: $AWS_RDS_ENDPOINT"
echo "S3 Bucket: $S3_BUCKET_NAME"
```

### Create Kubernetes Namespace
```bash
kubectl create namespace $NAMESPACE
kubectl config set-context --current --namespace=$NAMESPACE
```

### Create Secrets
```bash
# AWS Credentials
kubectl create secret generic aws-credentials \
  --from-literal=aws-region=$AWS_REGION \
  --from-literal=aws-access-key-id=$AWS_ACCESS_KEY_ID \
  --from-literal=aws-secret-access-key=$AWS_SECRET_ACCESS_KEY \
  -n $NAMESPACE

# RDS Credentials
kubectl create secret generic rds-credentials \
  --from-literal=aws-rds-endpoint=$AWS_RDS_ENDPOINT \
  --from-literal=aws-rds-dbname=$AWS_RDS_DBNAME \
  --from-literal=aws-rds-user=$AWS_RDS_USER \
  --from-literal=aws-rds-password=$AWS_RDS_PASSWORD \
  --from-literal=aws-rds-port=$AWS_RDS_PORT \
  -n $NAMESPACE

# S3 Configuration
kubectl create secret generic s3-config \
  --from-literal=s3-bucket-name=$S3_BUCKET_NAME \
  -n $NAMESPACE
```

## Deployment Commands

### Deploy Kafka Connect
```bash
# Apply Kubernetes manifests
envsubst < k8s/kafka-connect/configmap.yaml | kubectl apply -f -
envsubst < k8s/kafka-connect/service.yaml | kubectl apply -f -
envsubst < k8s/kafka-connect/deployment.yaml | kubectl apply -f -

# Wait for deployment
kubectl wait --for=condition=ready pod -l app=kafka-connect -n $NAMESPACE --timeout=300s

# Port forward for REST API access
kubectl port-forward service/kafka-connect 8083:8083 -n $NAMESPACE &
```

### Deploy Connectors
```bash
# Deploy Debezium PostgreSQL Connector
curl -X POST -H "Content-Type: application/json" \
  --data @connectors/debezium-postgres.json \
  http://localhost:8083/connectors

# Deploy S3 Sink Connector
curl -X POST -H "Content-Type: application/json" \
  --data @connectors/s3-sink.json \
  http://localhost:8083/connectors
```

## Connector Management

### List and Check Status
```bash
# List all connectors
curl -X GET http://localhost:8083/connectors

# Check connector status
curl -X GET http://localhost:8083/connectors/debezium-postgres/status | jq
curl -X GET http://localhost:8083/connectors/s3-sink/status | jq

# Get connector configuration
curl -X GET http://localhost:8083/connectors/debezium-postgres/config | jq
curl -X GET http://localhost:8083/connectors/s3-sink/config | jq
```

### Pause and Resume
```bash
# Pause connectors
curl -X PUT http://localhost:8083/connectors/debezium-postgres/pause
curl -X PUT http://localhost:8083/connectors/s3-sink/pause

# Resume connectors
curl -X PUT http://localhost:8083/connectors/debezium-postgres/resume
curl -X PUT http://localhost:8083/connectors/s3-sink/resume
```

### Update Configuration
```bash
# Update specific parameter
curl -X PUT -H "Content-Type: application/json" \
  --data '{"poll.interval.ms": "2000"}' \
  http://localhost:8083/connectors/debezium-postgres/config

# Update multiple parameters
curl -X PUT -H "Content-Type: application/json" \
  --data '{"max.batch.size": "4096", "flush.size": "1000"}' \
  http://localhost:8083/connectors/s3-sink/config
```

### Delete Connectors
```bash
# Delete connectors (use with caution)
curl -X DELETE http://localhost:8083/connectors/debezium-postgres
curl -X DELETE http://localhost:8083/connectors/s3-sink
```

## Monitoring and Health Checks

### Health Check Endpoints
```bash
# Kafka Connect health
curl http://localhost:8083/

# Connector plugins
curl http://localhost:8083/connector-plugins

# Worker information
curl http://localhost:8083/workers | jq
```

### Metrics and Monitoring
```bash
# Get all metrics
curl -s http://localhost:8083/metrics

# Filter specific metrics
curl -s http://localhost:8083/metrics | grep "kafka_connect_connector_task_metrics"
curl -s http://localhost:8083/metrics | grep "kafka_connect_sink_record_send_total"
curl -s http://localhost:8083/metrics | grep "kafka_connect_source_record_poll_total"
```

### Log Monitoring
```bash
# View Kafka Connect logs
kubectl logs -f deployment/kafka-connect -n $NAMESPACE

# Filter specific log patterns
kubectl logs deployment/kafka-connect -n $NAMESPACE | grep -i "error"
kubectl logs deployment/kafka-connect -n $NAMESPACE | grep -i "debezium"
kubectl logs deployment/kafka-connect -n $NAMESPACE | grep -i "s3"
```

## Troubleshooting Commands

### Check Pod Status
```bash
# Get pod status
kubectl get pods -n $NAMESPACE -l app=kafka-connect

# Describe pod for details
kubectl describe pod -l app=kafka-connect -n $NAMESPACE

# Check pod events
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'
```

### Network Connectivity
```bash
# Test database connectivity
kubectl exec -it deployment/kafka-connect -n $NAMESPACE -- \
  nc -zv $AWS_RDS_ENDPOINT $AWS_RDS_PORT

# Test RedPanda connectivity
kubectl exec -it deployment/kafka-connect -n $NAMESPACE -- \
  nc -zv redpanda-0.redpanda.cdc-project.svc.cluster.local 9093

# Test S3 connectivity
kubectl exec -it deployment/kafka-connect -n $NAMESPACE -- \
  aws s3 ls s3://$S3_BUCKET_NAME --region $AWS_REGION
```

### Database Verification
```sql
-- Check replication slot
SELECT * FROM pg_replication_slots WHERE slot_name = 'debezium_slot';

-- Check replication user permissions
SELECT grantee, privilege_type, table_name 
FROM information_schema.role_table_grants 
WHERE grantee = 'replicator';

-- Check WAL level
SHOW wal_level;
SHOW max_replication_slots;
SHOW max_wal_senders;
```

### Connector Validation
```bash
# Validate connector configuration
curl -X POST -H "Content-Type: application/json" \
  --data @connectors/debezium-postgres.json \
  http://localhost:8083/connector-plugins/PostgresConnector/config/validate

# Check connector tasks
curl -X GET http://localhost:8083/connectors/debezium-postgres/tasks | jq
curl -X GET http://localhost:8083/connectors/s3-sink/tasks | jq
```

## Data Validation

### Verify Kafka Topics
```bash
# List topics using RedPanda CLI
kubectl exec -it redpanda-0 -n $NAMESPACE -- rpk topic list

# Check topic details
kubectl exec -it redpanda-0 -n $NAMESPACE -- rpk topic describe dbz.public.users

# Check topic messages
kubectl exec -it redpanda-0 -n $NAMESPACE -- rpk topic consume dbz.public.users --num 5
```

### Verify S3 Data
```bash
# List S3 objects
aws s3 ls s3://$S3_BUCKET_NAME/topics/ --recursive

# Check for Parquet files
aws s3 ls s3://$S3_BUCKET_NAME/topics/dbz.public.users/ --recursive | grep .parquet

# Download and inspect a file
aws s3 cp s3://$S3_BUCKET_NAME/topics/dbz.public.users/2024-01-15/part-00000.parquet ./sample.parquet
```

### Test Data Flow
```sql
-- Insert test data
INSERT INTO public.users (id, name, email, created_at) 
VALUES (999, 'Test User', 'test@example.com', NOW());

-- Update test data
UPDATE public.users 
SET name = 'Updated Test User' 
WHERE id = 999;

-- Delete test data
DELETE FROM public.users WHERE id = 999;
```

## Performance Monitoring

### Resource Usage
```bash
# Check resource usage
kubectl top pods -n $NAMESPACE

# Monitor resource usage over time
kubectl top pods -n $NAMESPACE --containers

# Check pod resource limits
kubectl describe pod -l app=kafka-connect -n $NAMESPACE | grep -A 10 "Limits:"
```

### Performance Metrics
```bash
# Check connector throughput
curl -s http://localhost:8083/metrics | grep "kafka_connect_source_record_poll_total"
curl -s http://localhost:8083/metrics | grep "kafka_connect_sink_record_send_total"

# Check lag
curl -s http://localhost:8083/metrics | grep "kafka_connect_sink_record_send_latency_avg"
curl -s http://localhost:8083/metrics | grep "kafka_connect_source_record_poll_latency_avg"

# Check error rates
curl -s http://localhost:8083/metrics | grep "kafka_connect_connector_task_metrics_record_send_failures_total"
```

### Scaling Operations
```bash
# Scale Kafka Connect horizontally
kubectl scale deployment kafka-connect --replicas=3 -n $NAMESPACE

# Scale connector tasks
curl -X PUT -H "Content-Type: application/json" \
  --data '{"tasks.max": "3"}' \
  http://localhost:8083/connectors/debezium-postgres/config

# Check task distribution
curl -X GET http://localhost:8083/connectors/debezium-postgres/tasks | jq
```

## Common Error Resolution

### Connector Failed to Start
```bash
# Check logs for specific errors
kubectl logs deployment/kafka-connect -n $NAMESPACE | grep -i "error"

# Restart connector
curl -X POST http://localhost:8083/connectors/debezium-postgres/restart

# Check database connectivity
kubectl exec -it deployment/kafka-connect -n $NAMESPACE -- \
  psql -h $AWS_RDS_ENDPOINT -U $AWS_RDS_USER -d $AWS_RDS_DBNAME -c "SELECT 1;"
```

### High Consumer Lag
```bash
# Check lag metrics
curl -s http://localhost:8083/metrics | grep "lag"

# Increase batch size
curl -X PUT -H "Content-Type: application/json" \
  --data '{"max.batch.size": "8192", "flush.size": "5000"}' \
  http://localhost:8083/connectors/s3-sink/config

# Scale up resources
kubectl patch deployment kafka-connect -n $NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"kafka-connect","resources":{"limits":{"memory":"4Gi","cpu":"2000m"}}}]}}}}'
```

### Memory Issues
```bash
# Check memory usage
kubectl top pods -n $NAMESPACE

# Increase memory limits
kubectl patch deployment kafka-connect -n $NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"kafka-connect","resources":{"limits":{"memory":"4Gi"},"requests":{"memory":"2Gi"}}}]}}}}'

# Optimize connector settings
curl -X PUT -H "Content-Type: application/json" \
  --data '{"max.queue.size": "8192", "max.batch.size": "1024"}' \
  http://localhost:8083/connectors/debezium-postgres/config
```

## Cleanup Commands

### Remove Connectors
```bash
# Delete connectors
curl -X DELETE http://localhost:8083/connectors/debezium-postgres
curl -X DELETE http://localhost:8083/connectors/s3-sink
```

### Remove Kubernetes Resources
```bash
# Delete deployment and related resources
kubectl delete deployment kafka-connect -n $NAMESPACE
kubectl delete service kafka-connect -n $NAMESPACE
kubectl delete configmap cdc-config -n $NAMESPACE
kubectl delete secret aws-credentials rds-credentials s3-config -n $NAMESPACE
```

### Clean Database
```sql
-- Drop replication slot
SELECT pg_drop_replication_slot('debezium_slot');

-- Drop replication user
DROP USER replicator;
```

## Useful Aliases

Add these to your shell profile for convenience:

```bash
# Kafka Connect aliases
alias kc-status='curl -s http://localhost:8083/connectors | jq'
alias kc-logs='kubectl logs -f deployment/kafka-connect -n $NAMESPACE'
alias kc-pods='kubectl get pods -n $NAMESPACE -l app=kafka-connect'
alias kc-port-forward='kubectl port-forward service/kafka-connect 8083:8083 -n $NAMESPACE'

# Connector aliases
alias debezium-status='curl -s http://localhost:8083/connectors/debezium-postgres/status | jq'
alias s3-status='curl -s http://localhost:8083/connectors/s3-sink/status | jq'
alias debezium-restart='curl -X POST http://localhost:8083/connectors/debezium-postgres/restart'
alias s3-restart='curl -X POST http://localhost:8083/connectors/s3-sink/restart'

# Monitoring aliases
alias kc-metrics='curl -s http://localhost:8083/metrics'
alias kc-top='kubectl top pods -n $NAMESPACE'
alias kc-events='kubectl get events -n $NAMESPACE --sort-by=".lastTimestamp"'
```

## Quick Reference Tables

### Connector Status Codes
| Status | Description | Action |
|--------|-------------|--------|
| `RUNNING` | Connector is running normally | Monitor |
| `PAUSED` | Connector is paused | Resume if needed |
| `FAILED` | Connector has failed | Check logs and restart |
| `UNASSIGNED` | Connector is not assigned to a worker | Check worker status |

### Common HTTP Status Codes
| Code | Description | Action |
|------|-------------|--------|
| `200` | Success | Continue |
| `409` | Connector already exists | Delete first or use different name |
| `404` | Connector not found | Check connector name |
| `500` | Internal server error | Check logs |

### Resource Limits by Workload
| Workload | Memory Request | Memory Limit | CPU Request | CPU Limit |
|----------|---------------|--------------|-------------|-----------|
| Small | 512Mi | 1Gi | 250m | 500m |
| Medium | 1Gi | 2Gi | 500m | 1000m |
| Large | 2Gi | 4Gi | 1000m | 2000m |

### Performance Tuning Parameters
| Parameter | Low Latency | High Throughput | Cost Optimized |
|-----------|-------------|-----------------|----------------|
| `max.batch.size` | 1024 | 8192 | 4096 |
| `poll.interval.ms` | 50 | 100 | 2000 |
| `flush.size` | 1 | 10000 | 50000 |
| `rotate.interval.ms` | 10000 | 300000 | 3600000 | 