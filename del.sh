# Xóa tất cả namespaces và resources
kubectl delete namespace cdc-project --force --grace-period=0
kubectl delete namespace kredpanda --force --grace-period=0

# Xóa tất cả Helm releases
helm uninstall redpanda -n cdc-project 2>/dev/null || true
helm uninstall redpanda-console -n cdc-project 2>/dev/null || true

# Xóa persistent volumes
kubectl delete pv --all --force --grace-period=0