# Kafka Connect Connector Setup Guide

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step-by-Step Setup](#step-by-step-setup)
4. [Connector Management](#connector-management)
5. [Validation and Testing](#validation-and-testing)
6. [Advanced Configuration](#advanced-configuration)

## Overview

This guide provides step-by-step instructions for setting up and managing Kafka Connect connectors in the CDC pipeline. It covers the complete lifecycle from initial deployment to ongoing maintenance.

## Prerequisites

Before starting, ensure you have:

- Kubernetes cluster running with RedPanda
- Environment variables configured (see `env.template`)
- AWS credentials and permissions
- PostgreSQL database with logical replication enabled
- S3 bucket created and accessible

## Step-by-Step Setup

### Step 1: Environment Preparation

1. **Load Environment Variables**

```bash
# Copy and customize the environment template
cp env.template env.sh
source env.sh

# Verify environment variables
echo "Namespace: $NAMESPACE"
echo "AWS Region: $AWS_REGION"
echo "RDS Endpoint: $AWS_RDS_ENDPOINT"
echo "S3 Bucket: $S3_BUCKET_NAME"
```

2. **Create Kubernetes Namespace**

```bash
kubectl create namespace $NAMESPACE
kubectl config set-context --current --namespace=$NAMESPACE
```

### Step 2: Create Kubernetes Secrets

1. **AWS Credentials Secret**

```bash
kubectl create secret generic aws-credentials \
  --from-literal=aws-region=$AWS_REGION \
  --from-literal=aws-access-key-id=$AWS_ACCESS_KEY_ID \
  --from-literal=aws-secret-access-key=$AWS_SECRET_ACCESS_KEY \
  -n $NAMESPACE
```

2. **RDS Credentials Secret**

```bash
kubectl create secret generic rds-credentials \
  --from-literal=aws-rds-endpoint=$AWS_RDS_ENDPOINT \
  --from-literal=aws-rds-dbname=$AWS_RDS_DBNAME \
  --from-literal=aws-rds-user=$AWS_RDS_USER \
  --from-literal=aws-rds-password=$AWS_RDS_PASSWORD \
  --from-literal=aws-rds-port=$AWS_RDS_PORT \
  -n $NAMESPACE
```

3. **S3 Configuration Secret**

```bash
kubectl create secret generic s3-config \
  --from-literal=s3-bucket-name=$S3_BUCKET_NAME \
  -n $NAMESPACE
```

### Step 3: Deploy Kafka Connect

1. **Apply Kubernetes Manifests**

```bash
# Apply ConfigMap
envsubst < k8s/kafka-connect/configmap.yaml | kubectl apply -f -

# Apply Service
envsubst < k8s/kafka-connect/service.yaml | kubectl apply -f -

# Apply Deployment
envsubst < k8s/kafka-connect/deployment.yaml | kubectl apply -f -
```

2. **Verify Deployment**

```bash
# Check pod status
kubectl get pods -n $NAMESPACE -l app=kafka-connect

# Check service
kubectl get svc -n $NAMESPACE -l app=kafka-connect

# Check logs
kubectl logs -f deployment/kafka-connect -n $NAMESPACE
```

### Step 4: Database Preparation

1. **Enable Logical Replication**

```sql
-- Connect to PostgreSQL and run:
ALTER SYSTEM SET wal_level = logical;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET max_wal_senders = 10;

-- Restart PostgreSQL to apply changes
```

2. **Create Replication User**

```sql
-- Create replication user
CREATE USER replicator REPLICATION LOGIN PASSWORD 'your_secure_password';

-- Grant necessary permissions
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replicator;
GRANT USAGE ON SCHEMA public TO replicator;

-- For specific tables (if needed)
GRANT SELECT ON TABLE public.your_table_name TO replicator;
```

3. **Create Replication Slot**

```sql
-- Create logical replication slot
SELECT pg_create_logical_replication_slot('debezium_slot', 'pgoutput');

-- Verify slot creation
SELECT * FROM pg_replication_slots;
```

### Step 5: Deploy Connectors

1. **Wait for Kafka Connect to be Ready**

```bash
# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=kafka-connect -n $NAMESPACE --timeout=300s

# Port forward to access REST API
kubectl port-forward service/kafka-connect 8083:8083 -n $NAMESPACE &
```

2. **Deploy Debezium PostgreSQL Connector**

```bash
# Create connector configuration
cat > debezium-connector.json << EOF
{
  "name": "debezium-postgres",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "$AWS_RDS_ENDPOINT",
    "database.user": "$AWS_RDS_USER",
    "database.password": "$AWS_RDS_PASSWORD",
    "database.dbname": "$AWS_RDS_DBNAME",
    "database.port": "$AWS_RDS_PORT",
    "topic.prefix": "dbz",
    "database.server.name": "aws-rds-postgres",
    "database.history.kafka.bootstrap.servers": "redpanda-0.redpanda.cdc-project.svc.cluster.local:9093,redpanda-1.redpanda.cdc-project.svc.cluster.local:9093,redpanda-2.redpanda.cdc-project.svc.cluster.local:9093",
    "database.history.kafka.topic": "schema-changes.postgres",
    "slot.name": "$REPLICATION_SLOT_NAME",
    "schema.include.list": "$POSTGRES_SCHEMA_TO_TRACK",
    "table.include.list": "$POSTGRES_SCHEMA_TO_TRACK.$POSTGRES_TABLE_TO_TRACK",
    "topic.creation.enable": "true",
    "topic.creation.default.partitions": "3",
    "topic.creation.default.replication.factor": "3",
    "include.schema.changes": "true",
    "snapshot.mode": "initial",
    "snapshot.locking.mode": "minimal",
    "max.queue.size": "16384",
    "max.batch.size": "2048",
    "poll.interval.ms": "1000",
    "errors.tolerance": "all",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "true",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "true",
    "plugin.name": "pgoutput"
  }
}
EOF

# Deploy connector
curl -X POST -H "Content-Type: application/json" \
  --data @debezium-connector.json \
  http://localhost:8083/connectors
```

3. **Deploy S3 Sink Connector**

```bash
# Create connector configuration
cat > s3-sink-connector.json << EOF
{
  "name": "s3-sink",
  "config": {
    "connector.class": "io.confluent.connect.s3.S3SinkConnector",
    "topics": "dbz.$POSTGRES_SCHEMA_TO_TRACK.$POSTGRES_TABLE_TO_TRACK",
    "topics.dir": "topics",
    "s3.region": "$AWS_REGION",
    "s3.bucket.name": "$S3_BUCKET_NAME",
    "s3.part.size": "5242880",
    "flush.size": "1",
    "rotate.interval.ms": "10000",
    "format.class": "io.confluent.connect.s3.format.parquet.ParquetFormat",
    "partitioner.class": "io.confluent.connect.storage.partitioner.TimeBasedPartitioner",
    "path.format": "yyyy-MM-dd",
    "partition.duration.ms": "3600000",
    "locale": "en-US",
    "timezone": "UTC",
    "timestamp.extractor": "Record",
    "timestamp.field": "ts_ms",
    "storage.class": "io.confluent.connect.s3.storage.S3Storage",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "true",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "true",
    "errors.tolerance": "all",
    "compression.type": "gzip",
    "parquet.codec": "snappy"
  }
}
EOF

# Deploy connector
curl -X POST -H "Content-Type: application/json" \
  --data @s3-sink-connector.json \
  http://localhost:8083/connectors
```

## Connector Management

### List Connectors

```bash
# List all connectors
curl -X GET http://localhost:8083/connectors

# Get connector status
curl -X GET http://localhost:8083/connectors/debezium-postgres/status
curl -X GET http://localhost:8083/connectors/s3-sink/status
```

### Pause and Resume Connectors

```bash
# Pause connector
curl -X PUT http://localhost:8083/connectors/debezium-postgres/pause

# Resume connector
curl -X PUT http://localhost:8083/connectors/debezium-postgres/resume
```

### Update Connector Configuration

```bash
# Get current configuration
curl -X GET http://localhost:8083/connectors/debezium-postgres/config

# Update configuration
curl -X PUT -H "Content-Type: application/json" \
  --data '{"poll.interval.ms": "2000"}' \
  http://localhost:8083/connectors/debezium-postgres/config
```

### Delete Connectors

```bash
# Delete connector (use with caution)
curl -X DELETE http://localhost:8083/connectors/debezium-postgres
curl -X DELETE http://localhost:8083/connectors/s3-sink
```

## Validation and Testing

### Step 1: Verify Connector Status

```bash
# Check connector status
curl -s http://localhost:8083/connectors/debezium-postgres/status | jq
curl -s http://localhost:8083/connectors/s3-sink/status | jq

# Expected output should show "RUNNING" state
```

### Step 2: Test Data Flow

1. **Generate Test Data in PostgreSQL**

```sql
-- Connect to PostgreSQL and insert test data
INSERT INTO public.users (id, name, email, created_at) 
VALUES (1, 'Test User', 'test@example.com', NOW());

UPDATE public.users 
SET name = 'Updated User' 
WHERE id = 1;

DELETE FROM public.users WHERE id = 1;
```

2. **Verify Kafka Topics**

```bash
# List topics (using RedPanda console or CLI)
kubectl exec -it redpanda-0 -n $NAMESPACE -- rpk topic list

# Check topic details
kubectl exec -it redpanda-0 -n $NAMESPACE -- rpk topic describe dbz.public.users
```

3. **Verify S3 Data**

```bash
# List S3 objects
aws s3 ls s3://$S3_BUCKET_NAME/topics/dbz.public.users/ --recursive

# Check for Parquet files
aws s3 ls s3://$S3_BUCKET_NAME/topics/dbz.public.users/ --recursive | grep .parquet
```

### Step 3: Monitor Metrics

```bash
# Get connector metrics
curl -s http://localhost:8083/metrics | grep -E "(connect|kafka)"

# Check specific metrics
curl -s http://localhost:8083/metrics | grep "kafka_connect_connector_task_metrics"
```

## Advanced Configuration

### Performance Tuning

1. **Debezium Connector Tuning**

```json
{
  "max.queue.size": "32768",
  "max.batch.size": "4096",
  "poll.interval.ms": "500",
  "snapshot.fetch.size": "2048",
  "heartbeat.interval.ms": "5000"
}
```

2. **S3 Sink Connector Tuning**

```json
{
  "flush.size": "1000",
  "rotate.interval.ms": "60000",
  "s3.part.size": "10485760",
  "partition.duration.ms": "1800000"
}
```

### Error Handling Configuration

```json
{
  "errors.tolerance": "all",
  "errors.retry.timeout": "60000",
  "errors.retry.delay.max.ms": "1000",
  "errors.log.enable": "true",
  "errors.log.include.messages": "true"
}
```

### Monitoring Configuration

```yaml
# Add to deployment.yaml
- name: CONNECT_METRICS_REPORTERS
  value: "io.prometheus.jmx.BuildInfoCollector"
- name: CONNECT_JMX_PORT
  value: "9999"
- name: CONNECT_JMX_HOSTNAME
  value: "localhost"
```

### Scaling Configuration

```yaml
# Scale Kafka Connect horizontally
kubectl scale deployment kafka-connect --replicas=3 -n $NAMESPACE

# Configure connector tasks
curl -X PUT -H "Content-Type: application/json" \
  --data '{"tasks.max": "3"}' \
  http://localhost:8083/connectors/debezium-postgres/config
```

## Troubleshooting Commands

### Check Connector Logs

```bash
# View Kafka Connect logs
kubectl logs -f deployment/kafka-connect -n $NAMESPACE

# Check specific connector logs
kubectl logs deployment/kafka-connect -n $NAMESPACE | grep -i "debezium"
kubectl logs deployment/kafka-connect -n $NAMESPACE | grep -i "s3"
```

### Verify Database Connectivity

```bash
# Test database connection from pod
kubectl exec -it deployment/kafka-connect -n $NAMESPACE -- \
  nc -zv $AWS_RDS_ENDPOINT $AWS_RDS_PORT
```

### Check RedPanda Connectivity

```bash
# Test RedPanda connection
kubectl exec -it deployment/kafka-connect -n $NAMESPACE -- \
  nc -zv redpanda-0.redpanda.cdc-project.svc.cluster.local 9093
```

### Validate Configuration

```bash
# Validate connector configuration
curl -X POST -H "Content-Type: application/json" \
  --data @debezium-connector.json \
  http://localhost:8083/connector-plugins/PostgresConnector/config/validate
```

## Cleanup

### Remove Connectors

```bash
# Delete connectors
curl -X DELETE http://localhost:8083/connectors/debezium-postgres
curl -X DELETE http://localhost:8083/connectors/s3-sink
```

### Remove Kubernetes Resources

```bash
# Delete deployment
kubectl delete deployment kafka-connect -n $NAMESPACE

# Delete service
kubectl delete service kafka-connect -n $NAMESPACE

# Delete configmap
kubectl delete configmap cdc-config -n $NAMESPACE

# Delete secrets
kubectl delete secret aws-credentials rds-credentials s3-config -n $NAMESPACE
```

### Clean Database

```sql
-- Drop replication slot
SELECT pg_drop_replication_slot('debezium_slot');

-- Drop replication user
DROP USER replicator;
```

## Conclusion

This guide provides comprehensive instructions for setting up and managing Kafka Connect connectors in your CDC pipeline. Follow these steps carefully and refer to the troubleshooting section if you encounter any issues.

For additional support, refer to:
- [Kafka Connect REST API Documentation](https://docs.confluent.io/platform/current/connect/references/restapi.html)
- [Debezium Connector Configuration](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Confluent S3 Sink Connector](https://docs.confluent.io/kafka-connect-s3-sink/current/configuration_options.html) 