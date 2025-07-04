# Kubernetes Local Usage Guide

## Table of Contents

1. [Overview](#overview)
2. [Setup Local Kubernetes](#setup-local-kubernetes)
3. [Basic kubectl Commands](#basic-kubectl-commands)
4. [Managing Resources](#managing-resources)
5. [Namespace Management](#namespace-management)
6. [Applying and Deleting Manifests](#applying-and-deleting-manifests)
7. [Service Access & Port Forwarding](#service-access--port-forwarding)
8. [Logs & Troubleshooting](#logs--troubleshooting)
9. [Cleanup](#cleanup)
10. [Tips & Best Practices](#tips--best-practices)

---

## Overview

This guide summarizes how to use Kubernetes (k8s) in a local development environment. It covers setup, essential commands, resource management, troubleshooting, and best practices for local clusters (e.g., Minikube, Docker Desktop, kind).

---

## Setup Local Kubernetes

### Popular Local Kubernetes Solutions
- **Docker Desktop** (with Kubernetes enabled)
- **Minikube**
- **kind** (Kubernetes IN Docker)

### Example: Start Minikube
```bash
minikube start
```

### Example: Enable Kubernetes in Docker Desktop
- Open Docker Desktop > Preferences > Kubernetes > Enable Kubernetes

---

## Basic kubectl Commands

| Action                | Command                                  |
|-----------------------|------------------------------------------|
| Check cluster status  | `kubectl cluster-info`                   |
| Current context       | `kubectl config current-context`         |
| List all contexts     | `kubectl config get-contexts`            |
| Switch context        | `kubectl config use-context <name>`      |
| Current namespace     | `kubectl config view --minify | grep namespace:` |
| List namespaces       | `kubectl get namespaces`                 |
| Check current path    | `pwd`                                   |

---

## Managing Resources

| Resource     | List                | Describe             | Delete All           |
|--------------|---------------------|----------------------|----------------------|
| Pods         | `kubectl get pods`  | `kubectl describe pod <name>` | `kubectl delete pods --all` |
| Deployments  | `kubectl get deployments` | `kubectl describe deployment <name>` | `kubectl delete deployments --all` |
| Services     | `kubectl get services` | `kubectl describe service <name>` | `kubectl delete services --all` |
| All          | `kubectl get all`   |                      | `kubectl delete all --all` |

- Add `-n <namespace>` to target a specific namespace.
- Add `--all-namespaces` to list across all namespaces.

---

## Namespace Management

```bash
# List namespaces
kubectl get namespaces

# Create a namespace
kubectl create namespace my-namespace

# Delete a namespace
kubectl delete namespace my-namespace

# Use a namespace for all commands
kubectl config set-context --current --namespace=my-namespace
```

---

## Applying and Deleting Manifests

```bash
# Apply all manifests in a directory
kubectl apply -f k8s/

# Apply a single manifest
kubectl apply -f k8s/my-app.yaml

# Delete all resources defined in a directory
kubectl delete -f k8s/

# Delete a specific resource
kubectl delete -f k8s/my-app.yaml
```

---

## Service Access & Port Forwarding

```bash
# List services
kubectl get services

# Port forward a service to localhost
kubectl port-forward service/my-service 8080:80

# Port forward a pod
kubectl port-forward pod/my-pod 8080:80
```

---

## Logs & Troubleshooting

```bash
# View logs for a pod
kubectl logs <pod-name>

# View logs for all pods (loop)
for pod in $(kubectl get pods -o name); do kubectl logs $pod; done

# Describe a resource for detailed info
kubectl describe pod <pod-name>

# Get events (recent errors, warnings)
kubectl get events --sort-by='.lastTimestamp'
```

---

## Cleanup

```bash
# Delete all pods, services, deployments, etc. in current namespace
kubectl delete all --all

# Delete all resources in a specific namespace
kubectl delete all --all -n my-namespace

# Delete a namespace (removes all resources in it)
kubectl delete namespace my-namespace
```

---

## Tips & Best Practices

- Always check your current context and namespace before running destructive commands.
- Use namespaces to isolate projects or environments.
- Use `kubectl get all` to see all resources at a glance.
- Use `kubectl apply -f` for declarative, repeatable deployments.
- Use `kubectl port-forward` for local testing of services.
- Clean up unused resources to free up local system resources.
- Use YAML manifests and version control for all deployments.
- For advanced local testing, consider using tools like [skaffold](https://skaffold.dev/) or [Tilt](https://tilt.dev/).

---

## References
- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Minikube](https://minikube.sigs.k8s.io/docs/)
- [kind](https://kind.sigs.k8s.io/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) 