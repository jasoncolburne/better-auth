apiVersion: v1
kind: ServiceAccount
metadata:
  name: restart-controller
  namespace: ${environment.namespace}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployment-restarter
  namespace: ${environment.namespace}
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: restart-controller-binding
  namespace: ${environment.namespace}
subjects:
  - kind: ServiceAccount
    name: restart-controller
    namespace: ${environment.namespace}
roleRef:
  kind: Role
  name: deployment-restarter
  apiGroup: rbac.authorization.k8s.io
