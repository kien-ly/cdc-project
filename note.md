kubectl port-forward -n cdc-project svc/redpanda-console 9090:8080
kubectl port-forward -n cdc-project svc/kafka-connect 8083:8083

curl http://localhost:8083/connectors
curl http://localhost:8083/connectors/debezium-postgres/status
curl http://localhost:8083/connectors/s3-sink/status

kubectl --namespace cdc-project rollout status statefulset redpanda --watch

kubectl describe helmrelease redpanda --namespace cdc-project

  kubectl get pods -n "cdc-project" -l app.kubernetes.io/name=redpanda

kubectl exec -n "cdc-project" redpanda-0 -- rpk cluster health
kubectl exec -n "cdc-project" redpanda-0 -- rpk topic list

psql -h 192.192.192.105 -p 5432 -U postgres -d cdc_db

kubectl logs redpanda-1 --namespace cdc-project

kubectl exec -n cdc-project redpanda-0 -- rpk cluster health

kubectl logs -l app=kafka-connect -n cdc-project --tail=3

kubectl exec -n cdc-project -l app=kafka-connect -- curl -s http://localhost:8083/
kubectl exec -n "cdc-project" -l app=kafka-connect -- curl -s http://localhost:8083/ 


kubectl get pods -n "$NAMESPACE" -l app=kafka-connect -o jsonpath='{.items[0].metadata.name}'

kubectl logs -n cdc-project -l app=kafka-connect -f

https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.3.0.Final/debezium-connector-postgres-2.3.0.Final-plugin.tar.gz"

echo "\nChecking S3 Connector URL..." && curl -IsL "https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.3.0.Final/debezium-connector-postgres-2.3.0.Final-plugin.tar.gz" | head -n 1


          curl -fL -o /shared-plugins/debezium-connector-postgres/debezium-scripting-${DEBEZIUM_CONNECTOR_VERSION}.jar "https://repo1.maven.org/maven2/io/debezium/debezium-scripting/2.3.0.Final/debezium-scripting-2.3.0.Final.jar"


echo "\nChecking S3 Connector URL..." && curl -IsL "https://repo1.maven.org/maven2/io/debezium/debezium-scripting/2.3.0.Final/debezium-scripting-2.3.0.Final.jar" | head -n 1


echo "Downloading and extracting S3 Sink Connector..."
          curl -fL -o /tmp/kafka-connect-s3.zip "https://api.hub.confluent.io/api/plugins/confluentinc/kafka-connect-s3/versions/10.7.0/confluentinc-kafka-connect-s3-10.7.0.zip"
          unzip /tmp/kafka-connect-s3.zip -d /shared-plugins/


confluentinc-kafka-connect-s3-10.6.7.zip

kubectl port-forward -n cdc-project svc/redpanda-console 9090:8080


helm upgrade --install redpanda redpanda/redpanda --namespace cdc-project \
  --set external.enabled=true \
  --set external.type=LoadBalancer \
  --wait