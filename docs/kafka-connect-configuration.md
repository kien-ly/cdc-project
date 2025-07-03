# Kafka Connect Configuration Guide

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Configuration Files](#configuration-files)
5. [Kubernetes Deployment](#kubernetes-deployment)
6. [Connector Configuration](#connector-configuration)
7. [Environment Variables](#environment-variables)
8. [Security Configuration](#security-configuration)
9. [Monitoring and Health Checks](#monitoring-and-health-checks)
10. [Troubleshooting](#troubleshooting)
11. [Best Practices](#best-practices)

## Overview

This document provides a comprehensive guide to configuring Kafka Connect for Change Data Capture (CDC) from PostgreSQL to Amazon S3 using RedPanda as the message broker. The setup includes:

- **Debezium PostgreSQL Connector**: Captures database changes from PostgreSQL
- **S3 Sink Connector**: Sinks data to Amazon S3 in Parquet format
- **RedPanda**: High-performance Kafka-compatible message broker
- **Kubernetes Deployment**: Containerized deployment with proper resource management

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   PostgreSQL    │    │   Kafka Connect │    │    RedPanda     │    │   Amazon S3     │
│   (Source DB)   │───▶│   (CDC Engine)  │───▶│   (Message      │───▶│   (Data Lake)   │
│                 │    │                 │    │    Broker)      │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Data Flow

1. **Debezium Connector** monitors PostgreSQL WAL (Write-Ahead Log) for changes
2. **Changes are captured** and converted to Kafka messages
3. **RedPanda** stores the messages with replication factor 3
4. **S3 Sink Connector** consumes messages and writes to S3 in Parquet format
5. **Data is partitioned** by date for efficient querying

## Prerequisites

### Software Requirements

- Kubernetes cluster (EKS recommended)
- kubectl configured
- Helm 3.x
- AWS CLI configured
- PostgreSQL database with logical replication enabled

### AWS Resources

- RDS PostgreSQL instance with logical replication
- S3 bucket for data storage
- IAM roles and policies for access

### Database Requirements

```sql
-- Enable logical replication
ALTER SYSTEM SET wal_level = logical;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET max_wal_senders = 10;

-- Create replication user
CREATE USER replicator REPLICATION LOGIN PASSWORD 'your_password';

-- Grant necessary permissions
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replicator;
GRANT USAGE ON SCHEMA public TO replicator;
```

## Configuration Files

### 1. Debezium PostgreSQL Connector (`connectors/debezium-postgres.json`)

```json
{
  "name": "debezium-postgres",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "${AWS_RDS_ENDPOINT}",
    "database.user": "${AWS_RDS_USER}",
    "database.password": "${AWS_RDS_PASSWORD}",
    "database.dbname": "${AWS_RDS_DBNAME}",
    "database.port": "${AWS_RDS_PORT}",
    "topic.prefix": "dbz",
    "database.server.name": "aws-rds-postgres",
    "database.history.kafka.bootstrap.servers": "redpanda-0.redpanda.cdc-project.svc.cluster.local:9093,redpanda-1.redpanda.cdc-project.svc.cluster.local:9093,redpanda-2.redpanda.cdc-project.svc.cluster.local:9093",
    "database.history.kafka.topic": "schema-changes.postgres",
    "slot.name": "${REPLICATION_SLOT_NAME}",
    "schema.include.list": "${POSTGRES_SCHEMA_TO_TRACK}",
    "table.include.list": "${POSTGRES_SCHEMA_TO_TRACK}.${POSTGRES_TABLE_TO_TRACK}",
    "topic.creation.enable": "true",
    "topic.creation.default.partitions": "3",
    "topic.creation.default.replication.factor": "3",
    "topic.creation.groups": "cdc_group",
    "topic.creation.cdc_group.include": "${POSTGRES_SCHEMA_TO_TRACK}.${POSTGRES_TABLE_TO_TRACK}",
    "topic.creation.cdc_group.partitions": "3",
    "topic.creation.cdc_group.replication.factor": "3",
    "include.schema.changes": "true",
    "include.query": "false",
    "snapshot.mode": "initial",
    "snapshot.locking.mode": "minimal",
    "snapshot.delay.ms": "0",
    "snapshot.fetch.size": "1024",
    "max.queue.size": "16384",
    "max.batch.size": "2048",
    "poll.interval.ms": "1000",
    "heartbeat.interval.ms": "10000",
    "errors.max.retries": "3",
    "errors.retry.delay.max.ms": "500",
    "errors.retry.timeout.ms": "30000",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "true",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "true",
    "plugin.name": "pgoutput"
  }
}
```

#### Key Configuration Parameters

| Parameter | Description | Default | Recommended |
|-----------|-------------|---------|-------------|
| `connector.class` | Debezium PostgreSQL connector class | - | Required |
| `database.hostname` | PostgreSQL server hostname | - | RDS endpoint |
| `database.user` | Database user with replication privileges | - | replicator |
| `database.password` | Database password | - | Secure password |
| `topic.prefix` | Prefix for all Kafka topics | - | dbz |
| `slot.name` | Logical replication slot name | - | Unique name |
| `snapshot.mode` | Initial snapshot behavior | initial | initial |
| `snapshot.locking.mode` | Locking strategy during snapshot | minimal | minimal |
| `max.queue.size` | Maximum queue size for records | 16384 | 16384 |
| `max.batch.size` | Maximum batch size | 2048 | 2048 |
| `poll.interval.ms` | Polling interval | 1000 | 1000 |
| `errors.tolerance` | Error handling strategy | all | all |

### 2. S3 Sink Connector (`connectors/s3-sink.json`)

```json
{
  "name": "s3-sink",
  "config": {
    "connector.class": "io.confluent.connect.s3.S3SinkConnector",
    "topics": "dbz.${POSTGRES_SCHEMA_TO_TRACK}.${POSTGRES_TABLE_TO_TRACK}",
    "topics.dir": "topics",
    "s3.region": "${AWS_REGION}",
    "s3.bucket.name": "${S3_BUCKET_NAME}",
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
    "errors.retry.timeout": "30000",
    "errors.retry.delay.max.ms": "1000",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true",
    "behavior.on.null.values": "ignore",
    "behavior.on.malformed.documents": "warn",
    "compression.type": "gzip",
    "parquet.codec": "snappy"
  }
}
```

#### Key Configuration Parameters

| Parameter | Description | Default | Recommended |
|-----------|-------------|---------|-------------|
| `connector.class` | S3 sink connector class | - | Required |
| `topics` | Source topics to consume | - | dbz.schema.table |
| `s3.region` | AWS region for S3 bucket | - | us-east-1 |
| `s3.bucket.name` | S3 bucket name | - | Your bucket |
| `format.class` | Output format | - | ParquetFormat |
| `partitioner.class` | Partitioning strategy | - | TimeBasedPartitioner |
| `path.format` | Date format for partitioning | - | yyyy-MM-dd |
| `partition.duration.ms` | Partition duration | 3600000 | 3600000 (1 hour) |
| `flush.size` | Records per file | 1 | 1 |
| `rotate.interval.ms` | File rotation interval | 10000 | 10000 |
| `compression.type` | Compression type | gzip | gzip |
| `parquet.codec` | Parquet compression | snappy | snappy |

## Kubernetes Deployment

### 1. Deployment Configuration (`k8s/kafka-connect/deployment.yaml`)

The deployment includes:

- **Kafka Connect Container**: Main application container
- **Init Container**: Downloads and installs connectors
- **Resource Limits**: CPU and memory constraints
- **Health Checks**: Liveness and readiness probes
- **Volume Mounts**: Shared connector plugins

#### Key Features

```yaml
# Resource Management
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"

# Health Checks
livenessProbe:
  httpGet:
    path: /
    port: 8083
  initialDelaySeconds: 60
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /
    port: 8083
  initialDelaySeconds: 60
  periodSeconds: 15
  timeoutSeconds: 10
  failureThreshold: 5
```

### 2. Service Configuration (`k8s/kafka-connect/service.yaml`)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kafka-connect
  namespace: ${NAMESPACE}
  labels:
    app: kafka-connect
    component: cdc-pipeline
spec:
  type: ClusterIP
  ports:
  - port: 8083
    targetPort: 8083
    protocol: TCP
    name: rest-api
  selector:
    app: kafka-connect
```

### 3. ConfigMap (`k8s/kafka-connect/configmap.yaml`)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cdc-config
  namespace: ${NAMESPACE}
  labels:
    app: cdc-config
    component: cdc-pipeline
data:
  # PostgreSQL CDC Configuration
  postgres-schema-to-track: "${POSTGRES_SCHEMA_TO_TRACK}"
  postgres-table-to-track: "${POSTGRES_TABLE_TO_TRACK}"
  replication-slot-name: "${REPLICATION_SLOT_NAME}"
  
  # Connector Versions
  debezium-connector-version: "${DEBEZIUM_CONNECTOR_VERSION}"
  s3-sink-connector-version: "${S3_SINK_CONNECTOR_VERSION}"
  
  # Kafka Connect Configuration
  connect-group-id: "cdc-connect-group"
  connect-config-storage-topic: "connect-configs"
  connect-offset-storage-topic: "connect-offsets"
  connect-status-storage-topic: "connect-status"
```

## Environment Variables

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `NAMESPACE` | Kubernetes namespace | cdc-project |
| `AWS_REGION` | AWS region | us-east-1 |
| `AWS_ACCESS_KEY_ID` | AWS access key | AKIA... |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | ... |
| `AWS_RDS_ENDPOINT` | RDS endpoint | mydb.cluster-xyz.us-east-1.rds.amazonaws.com |
| `AWS_RDS_DBNAME` | Database name | mydatabase |
| `AWS_RDS_USER` | Database user | replicator |
| `AWS_RDS_PASSWORD` | Database password | secure_password |
| `AWS_RDS_PORT` | Database port | 5432 |
| `S3_BUCKET_NAME` | S3 bucket name | my-cdc-bucket |
| `POSTGRES_SCHEMA_TO_TRACK` | Schema to monitor | public |
| `POSTGRES_TABLE_TO_TRACK` | Table to monitor | users |
| `REPLICATION_SLOT_NAME` | Replication slot name | debezium_slot |
| `DEBEZIUM_CONNECTOR_VERSION` | Debezium version | 2.4.0 |
| `S3_SINK_CONNECTOR_VERSION` | S3 connector version | 14.0.0 |

### Environment Template (`env.template`)

```bash
# Kubernetes Configuration
export NAMESPACE="cdc-project"

# AWS Configuration
export AWS_REGION="us-east-1"
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"

# RDS Configuration
export AWS_RDS_ENDPOINT="your-rds-endpoint"
export AWS_RDS_DBNAME="your-database"
export AWS_RDS_USER="replicator"
export AWS_RDS_PASSWORD="your-password"
export AWS_RDS_PORT="5432"

# S3 Configuration
export S3_BUCKET_NAME="your-s3-bucket"

# CDC Configuration
export POSTGRES_SCHEMA_TO_TRACK="public"
export POSTGRES_TABLE_TO_TRACK="users"
export REPLICATION_SLOT_NAME="debezium_slot"

# Connector Versions
export DEBEZIUM_CONNECTOR_VERSION="2.4.0"
export S3_SINK_CONNECTOR_VERSION="14.0.0"
```

## Security Configuration

### 1. Kubernetes Secrets

Create secrets for sensitive data:

```bash
# AWS Credentials Secret
kubectl create secret generic aws-credentials \
  --from-literal=aws-region=$AWS_REGION \
  --from-literal=aws-access-key-id=$AWS_ACCESS_KEY_ID \
  --from-literal=aws-secret-access-key=$AWS_SECRET_ACCESS_KEY \
  -n $NAMESPACE

# RDS Credentials Secret
kubectl create secret generic rds-credentials \
  --from-literal=aws-rds-endpoint=$AWS_RDS_ENDPOINT \
  --from-literal=aws-rds-dbname=$AWS_RDS_DBNAME \
  --from-literal=aws-rds-user=$AWS_RDS_USER \
  --from-literal=aws-rds-password=$AWS_RDS_PASSWORD \
  --from-literal=aws-rds-port=$AWS_RDS_PORT \
  -n $NAMESPACE

# S3 Configuration Secret
kubectl create secret generic s3-config \
  --from-literal=s3-bucket-name=$S3_BUCKET_NAME \
  -n $NAMESPACE
```

### 2. IAM Policies

Required AWS IAM policies:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-bucket-name",
        "arn:aws:s3:::your-bucket-name/*"
      ]
    }
  ]
}
```

### 3. Network Security

- **VPC Configuration**: Ensure RedPanda and Kafka Connect are in the same VPC
- **Security Groups**: Configure appropriate ingress/egress rules
- **TLS/SSL**: Enable encryption for Kafka connections

## Monitoring and Health Checks

### 1. Health Check Endpoints

```bash
# Kafka Connect Health
curl http://kafka-connect:8083/

# Connector Status
curl http://kafka-connect:8083/connectors/debezium-postgres/status

# Connector Configuration
curl http://kafka-connect:8083/connectors/debezium-postgres/config
```

### 2. Metrics and Monitoring

#### Key Metrics to Monitor

- **Connector Status**: Running, failed, paused
- **Record Processing Rate**: Records per second
- **Lag**: Consumer lag for each partition
- **Error Rate**: Number of failed records
- **Memory Usage**: JVM heap usage
- **CPU Usage**: Container CPU utilization

#### Prometheus Metrics

Kafka Connect exposes metrics on `/metrics` endpoint:

```bash
curl http://kafka-connect:8083/metrics
```

### 3. Logging Configuration

```yaml
# Logging Environment Variables
- name: CONNECT_LOG4J_ROOT_LOGLEVEL
  value: "INFO"
- name: CONNECT_LOG4J_LOGGERS
  value: "org.apache.kafka.connect.runtime.rest=WARN,org.reflections=ERROR"
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Connector Fails to Start

**Symptoms**: Connector status shows "FAILED"

**Diagnosis**:
```bash
# Check connector logs
kubectl logs -f deployment/kafka-connect -n $NAMESPACE

# Check connector status
curl http://kafka-connect:8083/connectors/debezium-postgres/status
```

**Common Causes**:
- Database connection issues
- Missing replication slot
- Insufficient permissions
- Invalid configuration

**Solutions**:
```sql
-- Create replication slot manually
SELECT pg_create_logical_replication_slot('debezium_slot', 'pgoutput');

-- Grant permissions
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replicator;
GRANT USAGE ON SCHEMA public TO replicator;
```

#### 2. High Consumer Lag

**Symptoms**: S3 sink connector shows high lag

**Diagnosis**:
```bash
# Check consumer lag
curl http://kafka-connect:8083/connectors/s3-sink/status
```

**Solutions**:
- Increase `flush.size` and `rotate.interval.ms`
- Scale up Kafka Connect replicas
- Optimize S3 upload settings

#### 3. Memory Issues

**Symptoms**: Container restarts due to OOM

**Solutions**:
```yaml
# Increase memory limits
resources:
  requests:
    memory: "2Gi"
    cpu: "500m"
  limits:
    memory: "4Gi"
    cpu: "1000m"
```

#### 4. Network Connectivity Issues

**Symptoms**: Cannot connect to RedPanda or RDS

**Diagnosis**:
```bash
# Test connectivity
kubectl exec -it deployment/kafka-connect -n $NAMESPACE -- nc -zv redpanda-0.redpanda.cdc-project.svc.cluster.local 9093
```

**Solutions**:
- Verify network policies
- Check security groups
- Ensure proper DNS resolution

### Debugging Commands

```bash
# Check pod status
kubectl get pods -n $NAMESPACE

# View logs
kubectl logs -f deployment/kafka-connect -n $NAMESPACE

# Execute commands in container
kubectl exec -it deployment/kafka-connect -n $NAMESPACE -- /bin/bash

# Check connector plugins
kubectl exec -it deployment/kafka-connect -n $NAMESPACE -- ls -la /usr/share/confluent-hub-components

# Test REST API
kubectl port-forward service/kafka-connect 8083:8083 -n $NAMESPACE
curl http://localhost:8083/connectors
```

## Best Practices

### 1. Configuration Best Practices

- **Use Environment Variables**: Never hardcode sensitive values
- **Implement Proper Error Handling**: Set `errors.tolerance` appropriately
- **Configure Monitoring**: Set up alerts for connector failures
- **Use Resource Limits**: Prevent resource exhaustion
- **Implement Backup Strategies**: Regular backups of connector configurations

### 2. Performance Optimization

- **Batch Size Tuning**: Optimize `max.batch.size` and `flush.size`
- **Partitioning Strategy**: Use appropriate partitioning for S3
- **Compression**: Enable compression for better storage efficiency
- **Resource Allocation**: Monitor and adjust resource limits

### 3. Security Best Practices

- **Secret Management**: Use Kubernetes secrets for sensitive data
- **Network Security**: Implement proper network policies
- **Access Control**: Use least privilege principle
- **Encryption**: Enable encryption in transit and at rest

### 4. Operational Best Practices

- **Version Management**: Keep connectors updated
- **Testing**: Test configurations in staging environment
- **Documentation**: Maintain up-to-date documentation
- **Monitoring**: Implement comprehensive monitoring and alerting

### 5. Scaling Considerations

- **Horizontal Scaling**: Scale Kafka Connect horizontally
- **Partition Management**: Monitor partition count and distribution
- **Resource Planning**: Plan for growth in data volume
- **Backup and Recovery**: Implement disaster recovery procedures

## Conclusion

This comprehensive Kafka Connect configuration guide provides all the necessary information to set up and maintain a robust CDC pipeline from PostgreSQL to S3. By following these guidelines, you can ensure a reliable, scalable, and secure data streaming solution.

For additional support and troubleshooting, refer to:
- [Kafka Connect Documentation](https://docs.confluent.io/platform/current/connect/index.html)
- [Debezium Documentation](https://debezium.io/documentation/)
- [Confluent S3 Sink Connector](https://docs.confluent.io/kafka-connect-s3-sink/current/overview.html) 