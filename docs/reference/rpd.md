This guide will assist you in deploying a secure Redpanda cluster with SASL authentication on Amazon EKS using Helm.

Prerequisites
An EKS cluster with kubectl and helm configured.

Sufficient IAM permissions to create namespaces, secrets, and persistent volumes.

Access to the Redpanda Helm chart.

1. Create the Namespace


kubectl create namespace redpanda
2. Create SASL User Secrets
First, create a file named superusers.txt containing your superuser credentials:



superuser:<superuser-pw>:SCRAM-SHA-512
Next, create the secret in Kubernetes:



kubectl -n redpanda create secret generic redpanda-superusers --from-file=superusers.txt
kubectl -n redpanda create secret generic redpanda-bootstrap-user \
  --from-literal=username=superuser \
  --from-literal=password=<superuser-pw>
3. Add and Update the Redpanda Helm Repo


helm repo add redpanda <https://charts.redpanda.com>
helm repo update
4. Deploy Redpanda with SASL Authentication
Deploy Redpanda with 3 replicas and SASL enabled (note that TLS is disabled for demonstration purposes):



helm upgrade --install redpanda redpanda/redpanda \
  --version 5.10.2 \
  --namespace redpanda \
  --set statefulset.replicas=3 \
  --set tls.enabled=false \
  --set auth.sasl.enabled=true \
  --set auth.sasl.secretRef=redpanda-superusers \
  --set auth.sasl.bootstrapUser.name=superuser \
  --set auth.sasl.bootstrapUser.secretKeyRef.name=redpanda-bootstrap-user \
  --set auth.sasl.bootstrapUser.secretKeyRef.key=password \
  --set auth.sasl.bootstrapUser.mechanism=SCRAM-SHA-512 \
  --set "auth.sasl.users=null" \
  --set external.domain=vns-redpanda.local \
  --set "storage.persistentVolume.storageClass=gp3" \
  --wait \
  --timeout 1h
5. Verify Deployment
To check the status of Redpanda pods, run:



kubectl get pods -n redpanda
To review the Redpanda configuration, execute:



kubectl --namespace redpanda exec redpanda-0 -c redpanda -- cat etc/redpanda/redpanda.yaml
6. Create Application Users and ACLs
To create a new user (e.g., datahub), use the following command:



kubectl --namespace redpanda exec -ti redpanda-0 -c redpanda -- \
  rpk security user create datahub -p <datahub-password>
Next, grant permissions to the user:



kubectl exec --namespace redpanda -c redpanda redpanda-0 -- \
  rpk security acl create --allow-principal User:datahub \
  --operation all \
  --topic all \
  -X user=superuser -X pass=<superuser-pw> -X sasl.mechanism=SCRAM-SHA-512
7. Connect Clients
Utilize the internal service DNS names (e.g., redpanda-0.redpanda.redpanda.svc.cluster.local:9093).

Implement SASL/SCRAM-SHA-512 authentication with the created users.

8. Clean Up
To remove the Redpanda deployment, execute:



helm uninstall redpanda -n redpanda
kubectl delete namespace redpanda
References
Redpanda Docs

Redpanda Helm Chart

Redpanda Kubernetes Guide

