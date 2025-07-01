# Troubleshooting Guide

This guide covers common issues and their solutions for the CDC project deployment.

## Prerequisites Issues

### Docker Desktop Not Running
**Symptoms**: `docker info` fails or `kubectl cluster-info` shows connection refused
**Solution**: 
1. Start Docker Desktop
2. Enable Kubernetes in Docker Desktop settings
3. Wait for Kubernetes to be ready

### Missing Tools
**Symptoms**: Commands like `helm`, `kubectl`, `curl`, `jq` not found
**Solution**: Install missing tools:
```bash
# Install Helm
brew install helm

# Install kubectl
brew install kubectl

# Install jq
brew install jq
```

## Kubernetes Issues

### Namespace Already Exists
**Symptoms**: Error about namespace already existing
**Solution**: 
```bash
# Delete existing namespace
kubectl delete namespace cdc-project

# Or use a different namespace by updating .env file
```

### Pod Stuck in Pending
**Symptoms**: Pods remain in Pending state
**Solution**:
```bash
# Check pod events
kubectl describe pod <pod-name> -n cdc-project

# Check node resources
kubectl describe nodes

# Check if there are resource constraints
kubectl get events -n cdc-project
```

### Pod CrashLoopBackOff
**Symptoms**: Pods restarting repeatedly
**Solution**:
```bash
# Check pod logs
kubectl logs <pod-name> -n cdc-project

# Check pod description
kubectl describe pod <pod-name> -n cdc-project

# Check if secrets/configmaps exist
kubectl get secrets -n cdc-project
kubectl get configmaps -n cdc-project
```

## Redpanda Issues

### Redpanda Pods Not Ready
**Symptoms**: Redpanda pods not reaching Ready state
**Solution**:
```bash
# Check Redpanda logs
kubectl logs redpanda-0 -n cdc-project

# Check Redpanda cluster health
kubectl exec -n cdc-project redpanda-0 -- rpk cluster health

# Check if topics exist
kubectl exec -n cdc-project redpanda-0 -- rpk topic list
```

### Redpanda Storage Issues
**Symptoms**: Storage-related errors in logs
**Solution**:
```bash
# Check persistent volumes
kubectl get pv
kubectl get pvc -n cdc-project

# Check storage class
kubectl get storageclass
```

## Kafka Connect Issues

### Kafka Connect Pod Not Ready
**Symptoms**: Kafka Connect pod not reaching Ready state
**Solution**:
```bash
# Check Kafka Connect logs
kubectl logs -l app=kafka-connect -n cdc-project

# Check if connectors are downloaded
kubectl exec -n cdc-project <kafka-connect-pod> -- ls -la /usr/share/confluent-hub-components

# Check resource limits
kubectl describe pod -l app=kafka-connect -n cdc-project
```

### REST API Not Accessible
**Symptoms**: `curl http://localhost:8083/` fails
**Solution**:
```bash
# Check if port forwarding is active
kubectl get svc kafka-connect -n cdc-project

# Restart port forwarding
pkill -f "kubectl port-forward.*kafka-connect"
kubectl port-forward -n cdc-project svc/kafka-connect 8083:8083 &

# Check if service is working
kubectl exec -n cdc-project <kafka-connect-pod> -- curl -s http://localhost:8083/
```

### Connector Deployment Fails
**Symptoms**: Connector creation returns error
**Solution**:
```bash
# Check connector status
curl -s http://localhost:8083/connectors/debezium-postgres/status | jq

# Check connector config
curl -s http://localhost:8083/connectors/debezium-postgres/config | jq

# Check Kafka Connect logs for errors
kubectl logs -l app=kafka-connect -n cdc-project -f
```

## AWS Connectivity Issues

### RDS Connection Fails
**Symptoms**: Debezium connector cannot connect to RDS
**Solution**:
```bash
# Test RDS connectivity
PGPASSWORD=$AWS_RDS_PASSWORD psql -h $AWS_RDS_ENDPOINT -U $AWS_RDS_USER -d $AWS_RDS_DBNAME -c "SELECT 1;"

# Check RDS security groups
# Ensure your IP is allowed in RDS security group

# Check if logical replication is enabled
PGPASSWORD=$AWS_RDS_PASSWORD psql -h $AWS_RDS_ENDPOINT -U $AWS_RDS_USER -d $AWS_RDS_DBNAME -c "SHOW wal_level;"

# Check replication slot
PGPASSWORD=$AWS_RDS_PASSWORD psql -h $AWS_RDS_ENDPOINT -U $AWS_RDS_USER -d $AWS_RDS_DBNAME -c "SELECT * FROM pg_replication_slots;"
```

### S3 Access Fails
**Symptoms**: S3 Sink connector cannot write to S3
**Solution**:
```bash
# Test AWS credentials
aws sts get-caller-identity

# Test S3 bucket access
aws s3 ls s3://$S3_BUCKET_NAME

# Check S3 bucket permissions
aws s3api get-bucket-policy --bucket $S3_BUCKET_NAME
```

## Environment Variable Issues

### Missing Environment Variables
**Symptoms**: Script fails with "variable not set" errors
**Solution**:
```bash
# Check if .env file exists
ls -la .env

# Create .env file from template
cp env.template .env

# Edit .env file with your values
nano .env

# Source environment variables
source .env
```

### Invalid Environment Variables
**Symptoms**: Connectors fail with configuration errors
**Solution**:
```bash
# Validate environment variables
echo "RDS Endpoint: $AWS_RDS_ENDPOINT"
echo "S3 Bucket: $S3_BUCKET_NAME"
echo "Namespace: $NAMESPACE"

# Check for special characters in passwords
# Ensure no quotes around values in .env file
```

## Performance Issues

### High Memory Usage
**Symptoms**: Pods being killed due to OOM
**Solution**:
```bash
# Check resource usage
kubectl top pods -n cdc-project

# Increase resource limits in values.yaml
# Adjust connector batch sizes and flush intervals
```

### Slow CDC Processing
**Symptoms**: High lag in connector status
**Solution**:
```bash
# Check connector lag
curl -s http://localhost:8083/connectors/debezium-postgres/status | jq '.tasks[].state'

# Adjust connector configuration:
# - Increase max.batch.size
# - Decrease poll.interval.ms
# - Increase max.queue.size
```

## Network Issues

### Port Forwarding Problems
**Symptoms**: Cannot access services from host
**Solution**:
```bash
# Check if ports are in use
lsof -i :8083
lsof -i :30092

# Kill existing port forwarding
pkill -f "kubectl port-forward"

# Restart port forwarding
kubectl port-forward -n cdc-project svc/kafka-connect 8083:8083 &
```

### DNS Resolution Issues
**Symptoms**: Pods cannot resolve internal service names
**Solution**:
```bash
# Check DNS resolution
kubectl exec -n cdc-project redpanda-0 -- nslookup kafka-connect.cdc-project.svc.cluster.local

# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

## Cleanup Issues

### Incomplete Cleanup
**Symptoms**: Resources remain after cleanup
**Solution**:
```bash
# Force delete namespace
kubectl delete namespace cdc-project --force --grace-period=0

# Delete persistent volumes
kubectl delete pv --all

# Clean up port forwarding
pkill -f "kubectl port-forward"

# Remove local files
rm -f .port-forward.pid
```

## Getting Help

### Collecting Debug Information
```bash
# Collect all relevant information
kubectl get all -n cdc-project -o yaml > debug-k8s.yaml
kubectl logs -l app=kafka-connect -n cdc-project > debug-connect.log
kubectl logs redpanda-0 -n cdc-project > debug-redpanda.log
curl -s http://localhost:8083/connectors | jq > debug-connectors.json
```

### Common Log Locations
- Kafka Connect logs: `kubectl logs -l app=kafka-connect -n cdc-project`
- Redpanda logs: `kubectl logs redpanda-0 -n cdc-project`
- Connector status: `curl -s http://localhost:8083/connectors/<connector>/status`

### Useful Commands for Debugging
```bash
# Check all resources
kubectl get all -n cdc-project

# Check events
kubectl get events -n cdc-project --sort-by='.lastTimestamp'

# Check pod details
kubectl describe pod <pod-name> -n cdc-project

# Check service endpoints
kubectl get endpoints -n cdc-project

# Check secrets
kubectl get secrets -n cdc-project -o yaml
``` 