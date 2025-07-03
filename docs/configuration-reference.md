# Kafka Connect Configuration Reference

## Table of Contents

1. [Overview](#overview)
2. [Debezium PostgreSQL Connector](#debezium-postgresql-connector)
3. [S3 Sink Connector](#s3-sink-connector)
4. [Kafka Connect Worker Configuration](#kafka-connect-worker-configuration)
5. [Environment Variables Reference](#environment-variables-reference)
6. [Performance Tuning Guide](#performance-tuning-guide)
7. [Security Configuration](#security-configuration)

## Overview

This document provides a comprehensive reference for all configuration parameters used in the Kafka Connect CDC pipeline. Each parameter is explained with its purpose, default values, and recommended settings.

## Debezium PostgreSQL Connector

### Database Connection Parameters

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `connector.class` | String | - | Yes | Debezium PostgreSQL connector class |
| `database.hostname` | String | - | Yes | PostgreSQL server hostname or IP address |
| `database.port` | Integer | 5432 | No | PostgreSQL server port |
| `database.user` | String | - | Yes | Database user with replication privileges |
| `database.password` | String | - | Yes | Database user password |
| `database.dbname` | String | - | Yes | Database name to connect to |

**Example:**
```json
{
  "database.hostname": "my-rds-cluster.cluster-xyz.us-east-1.rds.amazonaws.com",
  "database.port": "5432",
  "database.user": "replicator",
  "database.password": "secure_password",
  "database.dbname": "mydatabase"
}
```

### Replication Configuration

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `slot.name` | String | - | Yes | Logical replication slot name |
| `plugin.name` | String | `decoderbufs` | No | Logical decoding plugin (use `pgoutput` for PostgreSQL 10+) |
| `database.server.name` | String | - | Yes | Logical name for the database server |
| `topic.prefix` | String | - | Yes | Prefix for all Kafka topics created by this connector |

**Example:**
```json
{
  "slot.name": "debezium_slot",
  "plugin.name": "pgoutput",
  "database.server.name": "aws-rds-postgres",
  "topic.prefix": "dbz"
}
```

### Schema and Table Filtering

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `schema.include.list` | String | - | No | Comma-separated list of schemas to include |
| `schema.exclude.list` | String | - | No | Comma-separated list of schemas to exclude |
| `table.include.list` | String | - | No | Comma-separated list of tables to include |
| `table.exclude.list` | String | - | No | Comma-separated list of tables to exclude |
| `column.include.list` | String | - | No | Comma-separated list of columns to include |
| `column.exclude.list` | String | - | No | Comma-separated list of columns to exclude |

**Example:**
```json
{
  "schema.include.list": "public,analytics",
  "table.include.list": "public.users,public.orders,analytics.events",
  "column.exclude.list": "public.users.password,public.users.ssn"
}
```

### Snapshot Configuration

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `snapshot.mode` | String | `initial` | No | Snapshot mode: `initial`, `never`, `when_needed`, `schema_only` |
| `snapshot.locking.mode` | String | `minimal` | No | Locking strategy: `minimal`, `shared`, `exclusive` |
| `snapshot.delay.ms` | Long | 0 | No | Delay before starting snapshot |
| `snapshot.fetch.size` | Integer | 1024 | No | Number of rows to fetch per batch during snapshot |
| `snapshot.max.threads` | Integer | 1 | No | Number of threads for parallel snapshot |

**Example:**
```json
{
  "snapshot.mode": "initial",
  "snapshot.locking.mode": "minimal",
  "snapshot.delay.ms": "0",
  "snapshot.fetch.size": "2048",
  "snapshot.max.threads": "2"
}
```

### Performance Tuning

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `max.queue.size` | Integer | 16384 | No | Maximum number of records in the queue |
| `max.batch.size` | Integer | 2048 | No | Maximum number of records in a batch |
| `poll.interval.ms` | Long | 1000 | No | Polling interval in milliseconds |
| `heartbeat.interval.ms` | Long | 10000 | No | Heartbeat interval in milliseconds |
| `min.row.count.to.stream.results` | Integer | 1000 | No | Minimum rows before streaming results |

**Example:**
```json
{
  "max.queue.size": "32768",
  "max.batch.size": "4096",
  "poll.interval.ms": "500",
  "heartbeat.interval.ms": "5000",
  "min.row.count.to.stream.results": "500"
}
```

### Error Handling

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `errors.tolerance` | String | `stop` | No | Error tolerance: `stop`, `all`, `none` |
| `errors.max.retries` | Integer | 3 | No | Maximum number of retries |
| `errors.retry.delay.max.ms` | Long | 500 | No | Maximum delay between retries |
| `errors.retry.timeout.ms` | Long | 30000 | No | Timeout for retries |
| `errors.log.enable` | Boolean | false | No | Enable error logging |
| `errors.log.include.messages` | Boolean | false | No | Include error messages in logs |

**Example:**
```json
{
  "errors.tolerance": "all",
  "errors.max.retries": "5",
  "errors.retry.delay.max.ms": "1000",
  "errors.retry.timeout.ms": "60000",
  "errors.log.enable": "true",
  "errors.log.include.messages": "true"
}
```

### Topic Configuration

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `topic.creation.enable` | Boolean | false | No | Enable automatic topic creation |
| `topic.creation.default.partitions` | Integer | 1 | No | Default number of partitions |
| `topic.creation.default.replication.factor` | Integer | 1 | No | Default replication factor |
| `topic.creation.groups` | String | - | No | Topic creation groups |
| `topic.creation.cdc_group.include` | String | - | No | Tables to include in CDC group |
| `topic.creation.cdc_group.partitions` | Integer | 3 | No | Partitions for CDC group |
| `topic.creation.cdc_group.replication.factor` | Integer | 3 | No | Replication factor for CDC group |

**Example:**
```json
{
  "topic.creation.enable": "true",
  "topic.creation.default.partitions": "3",
  "topic.creation.default.replication.factor": "3",
  "topic.creation.groups": "cdc_group",
  "topic.creation.cdc_group.include": "public.users,public.orders",
  "topic.creation.cdc_group.partitions": "3",
  "topic.creation.cdc_group.replication.factor": "3"
}
```

### Data Format Configuration

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `key.converter` | String | - | Yes | Key converter class |
| `key.converter.schemas.enable` | Boolean | true | No | Enable schemas in key |
| `value.converter` | String | - | Yes | Value converter class |
| `value.converter.schemas.enable` | Boolean | true | No | Enable schemas in value |
| `include.schema.changes` | Boolean | true | No | Include schema change events |
| `include.query` | Boolean | false | No | Include the original query |

**Example:**
```json
{
  "key.converter": "org.apache.kafka.connect.json.JsonConverter",
  "key.converter.schemas.enable": "true",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "true",
  "include.schema.changes": "true",
  "include.query": "false"
}
```

## S3 Sink Connector

### Basic Configuration

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `connector.class` | String | - | Yes | S3 sink connector class |
| `topics` | String | - | Yes | Comma-separated list of topics to consume |
| `topics.dir` | String | `topics` | No | Directory structure for topics |
| `s3.region` | String | - | Yes | AWS region for S3 bucket |
| `s3.bucket.name` | String | - | Yes | S3 bucket name |

**Example:**
```json
{
  "connector.class": "io.confluent.connect.s3.S3SinkConnector",
  "topics": "dbz.public.users,dbz.public.orders",
  "topics.dir": "topics",
  "s3.region": "us-east-1",
  "s3.bucket.name": "my-cdc-bucket"
}
```

### S3 Storage Configuration

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `storage.class` | String | - | Yes | Storage class implementation |
| `s3.part.size` | Integer | 5242880 | No | S3 part size in bytes |
| `s3.retry.backoff.ms` | Long | 200 | No | Backoff time between retries |
| `s3.retry.timeout.ms` | Long | 20000 | No | Timeout for S3 operations |
| `s3.acl.canned` | String | - | No | Canned ACL for S3 objects |

**Example:**
```json
{
  "storage.class": "io.confluent.connect.s3.storage.S3Storage",
  "s3.part.size": "10485760",
  "s3.retry.backoff.ms": "500",
  "s3.retry.timeout.ms": "30000",
  "s3.acl.canned": "private"
}
```

### Data Format Configuration

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `format.class` | String | - | Yes | Format class for data serialization |
| `compression.type` | String | `none` | No | Compression type: `none`, `gzip`, `snappy` |
| `parquet.codec` | String | `snappy` | No | Parquet compression codec |
| `avro.codec` | String | `null` | No | Avro compression codec |

**Example:**
```json
{
  "format.class": "io.confluent.connect.s3.format.parquet.ParquetFormat",
  "compression.type": "gzip",
  "parquet.codec": "snappy"
}
```

### Partitioning Configuration

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `partitioner.class` | String | - | Yes | Partitioner class for file organization |
| `path.format` | String | - | Yes | Date format for partitioning |
| `partition.duration.ms` | Long | - | Yes | Duration of each partition |
| `locale` | String | `en-US` | No | Locale for date formatting |
| `timezone` | String | `UTC` | No | Timezone for date formatting |
| `timestamp.extractor` | String | `Record` | No | Timestamp extraction method |
| `timestamp.field` | String | - | No | Field name containing timestamp |

**Example:**
```json
{
  "partitioner.class": "io.confluent.connect.storage.partitioner.TimeBasedPartitioner",
  "path.format": "yyyy-MM-dd",
  "partition.duration.ms": "3600000",
  "locale": "en-US",
  "timezone": "UTC",
  "timestamp.extractor": "Record",
  "timestamp.field": "ts_ms"
}
```

### Flush and Rotation Configuration

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `flush.size` | Integer | 10000 | No | Number of records per file |
| `rotate.interval.ms` | Long | - | No | Time-based file rotation |
| `rotate.schedule.interval.ms` | Long | - | No | Scheduled rotation interval |
| `timestamp.extractor` | String | `Record` | No | Timestamp extraction method |

**Example:**
```json
{
  "flush.size": "1000",
  "rotate.interval.ms": "60000",
  "rotate.schedule.interval.ms": "3600000",
  "timestamp.extractor": "Record"
}
```

### Error Handling

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `errors.tolerance` | String | `stop` | No | Error tolerance: `stop`, `all`, `none` |
| `errors.retry.timeout` | Long | 30000 | No | Timeout for retries |
| `errors.retry.delay.max.ms` | Long | 1000 | No | Maximum delay between retries |
| `errors.log.enable` | Boolean | false | No | Enable error logging |
| `errors.log.include.messages` | Boolean | false | No | Include error messages in logs |
| `behavior.on.null.values` | String | `include` | No | Behavior for null values |
| `behavior.on.malformed.documents` | String | `warn` | No | Behavior for malformed documents |

**Example:**
```json
{
  "errors.tolerance": "all",
  "errors.retry.timeout": "60000",
  "errors.retry.delay.max.ms": "2000",
  "errors.log.enable": "true",
  "errors.log.include.messages": "true",
  "behavior.on.null.values": "ignore",
  "behavior.on.malformed.documents": "warn"
}
```

## Kafka Connect Worker Configuration

### Basic Worker Settings

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `CONNECT_BOOTSTRAP_SERVERS` | String | - | Yes | Kafka bootstrap servers |
| `CONNECT_REST_PORT` | Integer | 8083 | No | REST API port |
| `CONNECT_GROUP_ID` | String | - | Yes | Worker group ID |
| `CONNECT_CONFIG_STORAGE_TOPIC` | String | - | Yes | Config storage topic |
| `CONNECT_OFFSET_STORAGE_TOPIC` | String | - | Yes | Offset storage topic |
| `CONNECT_STATUS_STORAGE_TOPIC` | String | - | Yes | Status storage topic |

**Example:**
```yaml
- name: CONNECT_BOOTSTRAP_SERVERS
  value: "redpanda-0.redpanda.cdc-project.svc.cluster.local:9093,redpanda-1.redpanda.cdc-project.svc.cluster.local:9093,redpanda-2.redpanda.cdc-project.svc.cluster.local:9093"
- name: CONNECT_REST_PORT
  value: "8083"
- name: CONNECT_GROUP_ID
  value: "cdc-connect-group"
- name: CONNECT_CONFIG_STORAGE_TOPIC
  value: "connect-configs"
- name: CONNECT_OFFSET_STORAGE_TOPIC
  value: "connect-offsets"
- name: CONNECT_STATUS_STORAGE_TOPIC
  value: "connect-status"
```

### Converter Configuration

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `CONNECT_KEY_CONVERTER` | String | - | Yes | Key converter class |
| `CONNECT_VALUE_CONVERTER` | String | - | Yes | Value converter class |
| `CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE` | Boolean | true | No | Enable schemas in key |
| `CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE` | Boolean | true | No | Enable schemas in value |
| `CONNECT_INTERNAL_KEY_CONVERTER` | String | - | Yes | Internal key converter |
| `CONNECT_INTERNAL_VALUE_CONVERTER` | String | - | Yes | Internal value converter |

**Example:**
```yaml
- name: CONNECT_KEY_CONVERTER
  value: "org.apache.kafka.connect.json.JsonConverter"
- name: CONNECT_VALUE_CONVERTER
  value: "org.apache.kafka.connect.json.JsonConverter"
- name: CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE
  value: "false"
- name: CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE
  value: "false"
- name: CONNECT_INTERNAL_KEY_CONVERTER
  value: "org.apache.kafka.connect.json.JsonConverter"
- name: CONNECT_INTERNAL_VALUE_CONVERTER
  value: "org.apache.kafka.connect.json.JsonConverter"
```

### Logging Configuration

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `CONNECT_LOG4J_ROOT_LOGLEVEL` | String | INFO | No | Root log level |
| `CONNECT_LOG4J_LOGGERS` | String | - | No | Specific logger configurations |
| `CONNECT_LOG4J_APPENDER_STDOUT_LAYOUT_CONVERSIONPATTERN` | String | - | No | Log pattern |

**Example:**
```yaml
- name: CONNECT_LOG4J_ROOT_LOGLEVEL
  value: "INFO"
- name: CONNECT_LOG4J_LOGGERS
  value: "org.apache.kafka.connect.runtime.rest=WARN,org.reflections=ERROR"
- name: CONNECT_LOG4J_APPENDER_STDOUT_LAYOUT_CONVERSIONPATTERN
  value: "[%d] %p %X{connector.context}%m (%c:%L)%n"
```

### Plugin Configuration

| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `CONNECT_PLUGIN_PATH` | String | - | Yes | Plugin path |
| `CONNECT_REST_ADVERTISED_HOST_NAME` | String | - | No | Advertised hostname |
| `CONNECT_REST_ADVERTISED_PORT` | Integer | - | No | Advertised port |

**Example:**
```yaml
- name: CONNECT_PLUGIN_PATH
  value: "/usr/share/java,/usr/share/confluent-hub-components"
- name: CONNECT_REST_ADVERTISED_HOST_NAME
  value: "kafka-connect.cdc-project.svc.cluster.local"
- name: CONNECT_REST_ADVERTISED_PORT
  value: "8083"
```

## Environment Variables Reference

### Kubernetes Configuration

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `NAMESPACE` | Kubernetes namespace | `cdc-project` | Yes |
| `KUBECONFIG` | Path to kubeconfig | `~/.kube/config` | No |

### AWS Configuration

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `AWS_REGION` | AWS region | `us-east-1` | Yes |
| `AWS_ACCESS_KEY_ID` | AWS access key | `AKIA...` | Yes |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | `...` | Yes |
| `AWS_DEFAULT_REGION` | Default AWS region | `us-east-1` | No |

### RDS Configuration

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `AWS_RDS_ENDPOINT` | RDS endpoint | `mydb.cluster-xyz.us-east-1.rds.amazonaws.com` | Yes |
| `AWS_RDS_DBNAME` | Database name | `mydatabase` | Yes |
| `AWS_RDS_USER` | Database user | `replicator` | Yes |
| `AWS_RDS_PASSWORD` | Database password | `secure_password` | Yes |
| `AWS_RDS_PORT` | Database port | `5432` | Yes |

### S3 Configuration

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `S3_BUCKET_NAME` | S3 bucket name | `my-cdc-bucket` | Yes |
| `S3_BUCKET_REGION` | S3 bucket region | `us-east-1` | No |

### CDC Configuration

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `POSTGRES_SCHEMA_TO_TRACK` | Schema to monitor | `public` | Yes |
| `POSTGRES_TABLE_TO_TRACK` | Table to monitor | `users` | Yes |
| `REPLICATION_SLOT_NAME` | Replication slot name | `debezium_slot` | Yes |

### Connector Versions

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `DEBEZIUM_CONNECTOR_VERSION` | Debezium version | `2.4.0` | Yes |
| `S3_SINK_CONNECTOR_VERSION` | S3 connector version | `14.0.0` | Yes |

## Performance Tuning Guide

### Debezium Connector Tuning

#### High-Throughput Configuration

```json
{
  "max.queue.size": "65536",
  "max.batch.size": "8192",
  "poll.interval.ms": "100",
  "snapshot.fetch.size": "4096",
  "snapshot.max.threads": "4",
  "heartbeat.interval.ms": "5000",
  "min.row.count.to.stream.results": "100"
}
```

#### Low-Latency Configuration

```json
{
  "max.queue.size": "8192",
  "max.batch.size": "1024",
  "poll.interval.ms": "50",
  "snapshot.fetch.size": "1024",
  "heartbeat.interval.ms": "1000"
}
```

#### Memory-Optimized Configuration

```json
{
  "max.queue.size": "4096",
  "max.batch.size": "512",
  "poll.interval.ms": "2000",
  "snapshot.fetch.size": "512",
  "heartbeat.interval.ms": "30000"
}
```

### S3 Sink Connector Tuning

#### High-Throughput Configuration

```json
{
  "flush.size": "10000",
  "rotate.interval.ms": "300000",
  "s3.part.size": "20971520",
  "partition.duration.ms": "1800000",
  "compression.type": "snappy"
}
```

#### Low-Latency Configuration

```json
{
  "flush.size": "1",
  "rotate.interval.ms": "10000",
  "s3.part.size": "5242880",
  "partition.duration.ms": "600000",
  "compression.type": "none"
}
```

#### Cost-Optimized Configuration

```json
{
  "flush.size": "50000",
  "rotate.interval.ms": "3600000",
  "s3.part.size": "104857600",
  "partition.duration.ms": "86400000",
  "compression.type": "gzip"
}
```

### Resource Allocation

#### Small Workload (1-10 tables, <1M records/day)

```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

#### Medium Workload (10-50 tables, 1-10M records/day)

```yaml
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
```

#### Large Workload (50+ tables, >10M records/day)

```yaml
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

## Security Configuration

### Network Security

#### Security Groups

```json
{
  "IngressRules": [
    {
      "FromPort": 5432,
      "ToPort": 5432,
      "Protocol": "tcp",
      "SourceSecurityGroupId": "sg-kafka-connect"
    }
  ],
  "EgressRules": [
    {
      "FromPort": 0,
      "ToPort": 65535,
      "Protocol": "tcp",
      "DestinationSecurityGroupId": "sg-redpanda"
    },
    {
      "FromPort": 443,
      "ToPort": 443,
      "Protocol": "tcp",
      "CidrIp": "0.0.0.0/0"
    }
  ]
}
```

#### Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kafka-connect-network-policy
  namespace: cdc-project
spec:
  podSelector:
    matchLabels:
      app: kafka-connect
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: redpanda
    ports:
    - protocol: TCP
      port: 9093
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: redpanda
    ports:
    - protocol: TCP
      port: 9093
  - ports:
    - protocol: TCP
      port: 443
    - protocol: TCP
      port: 80
```

### Encryption Configuration

#### TLS/SSL Configuration

```yaml
- name: CONNECT_SECURITY_PROTOCOL
  value: "SSL"
- name: CONNECT_SSL_KEYSTORE_LOCATION
  value: "/etc/ssl/certs/kafka-connect.keystore.jks"
- name: CONNECT_SSL_KEYSTORE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: kafka-ssl-secret
      key: keystore-password
- name: CONNECT_SSL_KEY_PASSWORD
  valueFrom:
    secretKeyRef:
      name: kafka-ssl-secret
      key: key-password
- name: CONNECT_SSL_TRUSTSTORE_LOCATION
  value: "/etc/ssl/certs/kafka-connect.truststore.jks"
- name: CONNECT_SSL_TRUSTSTORE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: kafka-ssl-secret
      key: truststore-password
```

#### S3 Encryption

```json
{
  "s3.encryption.type": "sse-s3",
  "s3.encryption.key": "arn:aws:kms:us-east-1:123456789012:key/your-kms-key-id"
}
```

### Access Control

#### IAM Roles and Policies

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
        "arn:aws:s3:::my-cdc-bucket",
        "arn:aws:s3:::my-cdc-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "arn:aws:kms:us-east-1:123456789012:key/your-kms-key-id"
    }
  ]
}
```

#### RBAC Configuration

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: cdc-project
  name: kafka-connect-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/logs"]
  verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kafka-connect-rolebinding
  namespace: cdc-project
subjects:
- kind: ServiceAccount
  name: kafka-connect
  namespace: cdc-project
roleRef:
  kind: Role
  name: kafka-connect-role
  apiGroup: rbac.authorization.k8s.io
```

## Conclusion

This configuration reference provides comprehensive documentation for all parameters used in the Kafka Connect CDC pipeline. Use this guide to optimize your configuration based on your specific requirements and workload characteristics.

For additional information, refer to:
- [Debezium Connector Configuration](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Confluent S3 Sink Connector](https://docs.confluent.io/kafka-connect-s3-sink/current/configuration_options.html)
- [Kafka Connect Configuration](https://docs.confluent.io/platform/current/connect/references/allconfigs.html) 