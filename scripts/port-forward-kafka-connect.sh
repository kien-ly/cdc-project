#!/bin/bash

# Port-forward Kafka Connect REST API (8083) to localhost:8083
# Kills any existing port-forward on 8083 for Kafka Connect

NAMESPACE=${NAMESPACE:-cdc-project}
LOCAL_PORT=8083
REMOTE_PORT=8083
SERVICE_NAME=kafka-connect

echo "[INFO] Killing any existing port-forward on $LOCAL_PORT..."
pkill -f "kubectl port-forward.*${SERVICE_NAME}.*${LOCAL_PORT}" 2>/dev/null || true

echo "[INFO] Starting port-forward: $SERVICE_NAME ($NAMESPACE) $LOCAL_PORT:$REMOTE_PORT"
kubectl port-forward -n "$NAMESPACE" svc/$SERVICE_NAME $LOCAL_PORT:$REMOTE_PORT 