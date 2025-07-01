# Monitoring Guide

This guide covers monitoring and observability for the CDC pipeline.

## Monitoring Overview

The CDC pipeline consists of several components that need monitoring:
- **Redpanda Cluster**: Kafka-compatible streaming platform
- **Kafka Connect**: Connector framework
- **Debezium PostgreSQL Connector**: CDC source connector
- **S3 Sink Connector**: Data destination connector
- **AWS RDS PostgreSQL**: Source database
- **AWS S3**: Destination storage

## Key Metrics to Monitor

### 1. Redpanda Metrics

#### Cluster Health
```bash
# Check cluster health
kubectl exec -n cdc-project redpanda-0 -- rpk cluster health

# Check cluster info
kubectl exec -n cdc-project redpanda-0 -- rpk cluster info
```

#### Topic Metrics
```bash
# List topics
kubectl exec -n cdc-project redpanda-0 -- rpk topic list

# Get topic details
kubectl exec -n cdc-project redpanda-0 -- rpk topic describe <topic-name>

# Get topic offsets
kubectl exec -n cdc-project redpanda-0 -- rpk topic offset <topic-name>
```

#### Performance Metrics
```bash
# Check broker metrics
kubectl exec -n cdc-project redpanda-0 -- rpk cluster config get redpanda.enable_metrics

# Monitor resource usage
kubectl top pods -n cdc-project -l app.kubernetes.io/name=redpanda
```

### 2. Kafka Connect Metrics

#### Connector Status
```bash
# List all connectors
curl -s http://localhost:8083/connectors | jq

# Get connector status
curl -s http://localhost:8083/connectors/debezium-postgres/status | jq
curl -s http://localhost:8083/connectors/s3-sink/status | jq

# Get connector configuration
curl -s http://localhost:8083/connectors/debezium-postgres/config | jq
curl -s http://localhost:8083/connectors/s3-sink/config | jq
```

#### Task Status
```bash
# Get task status for Debezium connector
curl -s http://localhost:8083/connectors/debezium-postgres/status | jq '.tasks[] | {id: .id, state: .state, worker_id: .worker_id}'

# Get task status for S3 connector
curl -s http://localhost:8083/connectors/s3-sink/status | jq '.tasks[] | {id: .id, state: .state, worker_id: .worker_id}'
```

#### REST API Health
```bash
# Check REST API health
curl -s http://localhost:8083/ | jq

# Get connector plugins
curl -s http://localhost:8083/connector-plugins | jq
```

### 3. Debezium Connector Metrics

#### CDC Lag
```bash
# Check connector lag
curl -s http://localhost:8083/connectors/debezium-postgres/status | jq '.tasks[].state'

# Monitor lag in real-time
watch -n 5 'curl -s http://localhost:8083/connectors/debezium-postgres/status | jq'
```

#### Database Connection
```bash
# Test RDS connectivity
PGPASSWORD=$AWS_RDS_PASSWORD psql -h $AWS_RDS_ENDPOINT -U $AWS_RDS_USER -d $AWS_RDS_DBNAME -c "SELECT 1;"

# Check replication slot
PGPASSWORD=$AWS_RDS_PASSWORD psql -h $AWS_RDS_ENDPOINT -U $AWS_RDS_USER -d $AWS_RDS_DBNAME -c "SELECT slot_name, active, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots WHERE slot_name = '$REPLICATION_SLOT_NAME';"
```

#### Topic Messages
```bash
# Consume messages from CDC topic
kubectl exec -n cdc-project redpanda-0 -- rpk topic consume ${POSTGRES_SCHEMA_TO_TRACK}.${POSTGRES_TABLE_TO_TRACK} --num 10
```

### 4. S3 Sink Connector Metrics

#### S3 Upload Status
```bash
# Check connector status
curl -s http://localhost:8083/connectors/s3-sink/status | jq

# Monitor S3 uploads
aws s3 ls s3://$S3_BUCKET_NAME --recursive | tail -10
```

#### File Generation
```bash
# Count files in S3
aws s3 ls s3://$S3_BUCKET_NAME --recursive | wc -l

# Check file sizes
aws s3 ls s3://$S3_BUCKET_NAME --recursive --human-readable
```

### 5. System Resource Metrics

#### Pod Resource Usage
```bash
# Monitor pod resource usage
kubectl top pods -n cdc-project

# Get detailed resource information
kubectl describe pods -n cdc-project
```

#### Node Resource Usage
```bash
# Check node resources
kubectl top nodes

# Get node details
kubectl describe nodes
```

## Log Monitoring

### 1. Kafka Connect Logs
```bash
# Follow Kafka Connect logs
kubectl logs -l app=kafka-connect -n cdc-project -f

# Get recent logs
kubectl logs -l app=kafka-connect -n cdc-project --tail=100

# Get logs for specific pod
kubectl logs <kafka-connect-pod-name> -n cdc-project
```

### 2. Redpanda Logs
```bash
# Follow Redpanda logs
kubectl logs redpanda-0 -n cdc-project -f

# Get recent logs
kubectl logs redpanda-0 -n cdc-project --tail=100
```

### 3. Connector-Specific Logs
```bash
# Filter logs for specific connector
kubectl logs -l app=kafka-connect -n cdc-project | grep -i "debezium"

# Filter logs for errors
kubectl logs -l app=kafka-connect -n cdc-project | grep -i "error"
```

## Alerting and Health Checks

### 1. Health Check Script
Create a health check script to monitor the entire pipeline:

```bash
#!/bin/bash
# health-check.sh

set -e

NAMESPACE=${NAMESPACE:-cdc-project}

echo "=== CDC Pipeline Health Check ==="
echo "Timestamp: $(date)"
echo ""

# Check Redpanda
echo "1. Redpanda Cluster Health:"
kubectl exec -n $NAMESPACE redpanda-0 -- rpk cluster health
echo ""

# Check Kafka Connect
echo "2. Kafka Connect Status:"
kubectl get pods -n $NAMESPACE -l app=kafka-connect
echo ""

# Check Connectors
echo "3. Connector Status:"
curl -s http://localhost:8083/connectors | jq '.[]' | while read connector; do
    echo "Connector: $connector"
    curl -s http://localhost:8083/connectors/$connector/status | jq '.tasks[].state'
done
echo ""

# Check S3
echo "4. S3 Data:"
aws s3 ls s3://$S3_BUCKET_NAME --recursive | tail -5
echo ""

echo "Health check completed at $(date)"
```

### 2. Automated Monitoring
Set up automated monitoring with cron jobs:

```bash
# Add to crontab for hourly health checks
0 * * * * /path/to/health-check.sh >> /var/log/cdc-health.log 2>&1

# Add to crontab for daily reports
0 9 * * * /path/to/health-check.sh | mail -s "CDC Pipeline Daily Report" admin@example.com
```

## Performance Monitoring

### 1. Throughput Metrics
```bash
# Monitor message throughput
kubectl exec -n cdc-project redpanda-0 -- rpk topic describe ${POSTGRES_SCHEMA_TO_TRACK}.${POSTGRES_TABLE_TO_TRACK} | grep -E "(partition|leader|replicas)"

# Check connector throughput
curl -s http://localhost:8083/connectors/debezium-postgres/status | jq '.tasks[] | {id: .id, state: .state}'
```

### 2. Latency Metrics
```bash
# Check connector lag
curl -s http://localhost:8083/connectors/debezium-postgres/status | jq '.tasks[].state'

# Monitor S3 upload latency
aws s3 ls s3://$S3_BUCKET_NAME --recursive | tail -1
```

### 3. Resource Utilization
```bash
# Monitor CPU and memory usage
kubectl top pods -n cdc-project

# Check disk usage
kubectl exec -n cdc-project redpanda-0 -- df -h
```

## Troubleshooting Monitoring

### 1. Common Issues
- **High Lag**: Check RDS performance and network connectivity
- **Memory Issues**: Monitor pod resource usage and adjust limits
- **S3 Upload Failures**: Check AWS credentials and bucket permissions
- **Connector Failures**: Review logs for specific error messages

### 2. Debug Commands
```bash
# Get comprehensive status
kubectl get all -n cdc-project

# Check events
kubectl get events -n cdc-project --sort-by='.lastTimestamp'

# Check service endpoints
kubectl get endpoints -n cdc-project

# Test connectivity
kubectl exec -n cdc-project redpanda-0 -- ping kafka-connect.cdc-project.svc.cluster.local
```

## Best Practices

### 1. Regular Monitoring
- Set up automated health checks
- Monitor resource usage trends
- Track connector performance metrics
- Review logs regularly

### 2. Alerting
- Set up alerts for connector failures
- Monitor for high lag conditions
- Alert on resource exhaustion
- Track S3 upload failures

### 3. Documentation
- Document monitoring procedures
- Keep runbooks for common issues
- Maintain performance baselines
- Update monitoring as the system evolves

### 4. Capacity Planning
- Monitor resource usage trends
- Plan for data growth
- Scale resources as needed
- Optimize connector configurations 