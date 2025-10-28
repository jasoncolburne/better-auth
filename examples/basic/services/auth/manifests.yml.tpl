apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth
  labels:
    app: auth
spec:
  replicas: 2
  selector:
    matchLabels:
      app: auth
  template:
    metadata:
      labels:
        app: auth
    spec:
      containers:
        - name: auth
          image: ${actions.build.auth.outputs.deployment-image-id}
          ports:
            - containerPort: 80
              name: http
          env:
            - name: REDIS_HOST
              value: "redis:6379"
            - name: REDIS_DB_ACCESS_KEYS
              value: "${variables.redisDbAccessKeys}"
            - name: REDIS_DB_RESPONSE_KEYS
              value: "${variables.redisDbResponseKeys}"
            - name: REDIS_DB_ACCESS_KEYHASH
              value: "${variables.redisDbAccessKeyHash}"
            - name: REDIS_DB_REVOKED_DEVICES
              value: "${variables.redisDbRevokedDevices}"
            - name: POSTGRES_HOST
              value: "postgres"
            - name: POSTGRES_PORT
              value: "5432"
            - name: POSTGRES_DATABASE
              value: "${variables.postgresDatabase}"
            - name: POSTGRES_USER
              value: "${variables.postgresUser}"
            - name: POSTGRES_PASSWORD
              value: "${variables.postgresPassword}"
            - name: HSM_HOST
              value: "${variables.hsmHost}"
            - name: HSM_PORT
              value: "${variables.hsmPort}"
          livenessProbe:
            httpGet:
              path: /health
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi

---

apiVersion: batch/v1
kind: CronJob
metadata:
  name: auth-rolling-restart
  namespace: ${environment.namespace}
spec:
  schedule: "0 */12 * * *"
  successfulJobsHistoryLimit: 0
  failedJobsHistoryLimit: 2
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      activeDeadlineSeconds: 300
      backoffLimit: 1
      template:
        spec:
          restartPolicy: Never
          serviceAccountName: restart-controller
          containers:
          - name: kubectl
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              kubectl rollout restart deployment auth -n ${environment.namespace}

---

apiVersion: v1
kind: Service
metadata:
  name: auth
  labels:
    app: auth
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
      name: http
  selector:
    app: auth

---

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: auth
  labels:
    app: auth
spec:
  ingressClassName: nginx
  rules:
    - host: auth.better-auth.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: auth
                port:
                  number: 80
