# Connecting Debezium PostgreSQL CDC to S3 via Redpanda on EKS

## Overview
This guide explains how to set up a Change Data Capture (CDC) pipeline using Debezium PostgreSQL as a source connector and S3 as a sink connector (Parquet format), with Kafka Connect connecting to an existing Redpanda cluster on Amazon EKS.


## Architecture
```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ PostgreSQL   │    │ Kafka Connect│    │  Redpanda    │    │   S3 Bucket  │
│ (RDS/EKS)    │───▶│  (Debezium)  │───▶│ (Kafka API)  │───▶│ (CDC Storage)│
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
```

---

## Prerequisites
- **Redpanda cluster** already running in EKS (see reference/rpd.md for setup)
- **kubectl** and **helm** configured for your EKS cluster
- **PostgreSQL** database with logical replication enabled
- **S3 bucket** and IAM permissions for access
- **Kafka Connect** Helm chart (e.g., Bitnami or Confluent)

---

## 1. Prepare Environment Values
Create a `values.yaml` file for your Kafka Connect Helm deployment. Example:

```yaml
replicaCount: 1
image:
  repository: bitnami/kafka-connect
  tag: 3.6.0
  pullPolicy: IfNotPresent
env:
  - name: AWS_REGION
    value: us-east-1
  - name: AWS_RDS_ENDPOINT
    value: <your-rds-endpoint>
  - name: AWS_RDS_DBNAME
    value: <your-db>
  - name: AWS_RDS_USER
    value: <your-user>
  - name: AWS_RDS_PASSWORD
    value: <your-password>
  - name: AWS_RDS_PORT
    value: "5432"
  - name: S3_BUCKET_NAME
    value: <your-s3-bucket>
  - name: POSTGRES_SCHEMA_TO_TRACK
    value: public
  - name: REPLICATION_SLOT_NAME
    value: debezium_slot
  - name: BOOTSTRAP_SERVERS
    value: redpanda-0.redpanda.svc.cluster.local:9093,redpanda-1.redpanda.svc.cluster.local:9093,redpanda-2.redpanda.svc.cluster.local:9093
```

**Important Notes:**
- The `BOOTSTRAP_SERVERS` value must match your Redpanda service endpoints in EKS.
- All sensitive values (passwords, keys) should be stored as Kubernetes secrets in production.
- Ensure network policies and security groups allow traffic between Kafka Connect, Redpanda, PostgreSQL, and S3.

---

## 2. Deploy Kafka Connect with Helm

```bash
kubectl create namespace $NAMESPACE
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm upgrade --install kafka-connect bitnami/kafka-connect \
  --namespace $NAMESPACE \
  -f values.yaml \
  --wait
```

---

## 3. Configure Debezium PostgreSQL Source Connector
Create a file named `debezium-postgres.json`:

```json
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
    "database.history.kafka.bootstrap.servers": "$BOOTSTRAP_SERVERS",
    "database.history.kafka.topic": "schema-changes.postgres",
    "slot.name": "$REPLICATION_SLOT_NAME",
    "schema.include.list": "$POSTGRES_SCHEMA_TO_TRACK",
    "table.include.list": "$POSTGRES_SCHEMA_TO_TRACK.*",
    "topic.creation.enable": "true",
    "topic.creation.default.partitions": "3",
    "topic.creation.default.replication.factor": "3",
    "topic.creation.groups": "cdc_group",
    "topic.creation.cdc_group.include": "$POSTGRES_SCHEMA_TO_TRACK.*",
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
```

**Important Notes:**
- `table.include.list` with `public.*` (or your schema) will capture all tables in the schema.
- Debezium will create one topic per table: `dbz.<schema>.<table>`.
- Ensure logical replication is enabled in PostgreSQL and the replication slot exists.

---

## 4. Configure S3 Sink Connector
Create a file named `s3-sink.json`:

```json
{
  "name": "s3-sink",
  "config": {
    "connector.class": "io.confluent.connect.s3.S3SinkConnector",
    "topics": "dbz.public.users,dbz.public.orders", // List all topics explicitly
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
```

**Important Notes:**
- You **must enumerate all topics** to be written to S3. Wildcards are not supported.
- The S3 Sink will write Parquet files to your S3 bucket, partitioned by date.
- Ensure the IAM role used by Kafka Connect has S3 write permissions.

---

## 5. Deploy Connectors
Substitute environment variables and deploy the connectors:

```bash
export $(cat values.yaml | grep 'value:' | sed 's/.*name: \(.*\)/\1/' | paste -d= - - | sed 's/ value=/=/g')

envsubst < debezium-postgres.json > /tmp/debezium-postgres.resolved.json
kubectl port-forward svc/kafka-connect 8083:8083 -n $NAMESPACE &
curl -X POST -H "Content-Type: application/json" \
  --data @/tmp/debezium-postgres.resolved.json \
  http://localhost:8083/connectors

envsubst < s3-sink.json > /tmp/s3-sink.resolved.json
curl -X POST -H "Content-Type: application/json" \
  --data @/tmp/s3-sink.resolved.json \
  http://localhost:8083/connectors
```

---

## 6. Validation & Monitoring
- **Check connector status:**
  ```bash
  curl http://localhost:8083/connectors/debezium-postgres/status
  curl http://localhost:8083/connectors/s3-sink/status
  ```
- **Check topics in Redpanda:**
  ```bash
  kubectl exec -it redpanda-0 -n redpanda -- rpk topic list
  ```
- **Check S3 output:**
  ```bash
  aws s3 ls s3://<your-s3-bucket>/topics/ --recursive
  ```
- **View logs:**
  ```bash
  kubectl logs -f deployment/kafka-connect -n $NAMESPACE
  ```

---

## 7. Important Setup Notes
- **Topic Naming:** Debezium creates one topic per table. S3 Sink requires explicit topic listing.
- **Environment Variable Substitution:** Always resolve variables before posting connector configs.
- **Network/Security:** Ensure all pods/services can communicate (Redpanda, Kafka Connect, Postgres, S3).
- **IAM Permissions:** Kafka Connect must have S3 write access.
- **Database Setup:** Logical replication and replication slot must be enabled and available.
- **Resource Limits:** Set appropriate CPU/memory for Kafka Connect in production.
- **Connector Restarts:** If you change connector configs, update via PUT or delete and recreate.
- **Namespace Customization:** Use the `$NAMESPACE` variable throughout to easily switch between environments.

---

## 8. Clean Up
To remove the Kafka Connect deployment:
```bash
helm uninstall kafka-connect -n $NAMESPACE
kubectl delete namespace $NAMESPACE
```

---

## References
- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Confluent S3 Sink Connector](https://docs.confluent.io/kafka-connect-s3-sink/current/overview.html)
- [Bitnami Kafka Connect Helm Chart](https://github.com/bitnami/charts/tree/main/bitnami/kafka-connect)
- [Redpanda EKS Setup](reference/rpd.md)
- [Kubernetes Documentation](https://kubernetes.io/docs/) 