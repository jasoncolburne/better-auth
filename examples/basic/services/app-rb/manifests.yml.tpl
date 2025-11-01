apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-rb
  labels:
    app: app-rb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-rb
  template:
    metadata:
      labels:
        app: app-rb
    spec:
      containers:
        - name: app-rb
          image: ${actions.build.app-rb.outputs.deployment-image-id}
          ports:
            - containerPort: 80
              name: http
          env:
            - name: REDIS_HOST
              value: "${variables.redisHost}:${variables.redisPort}"
            - name: REDIS_DB_ACCESS_KEYS
              value: "${variables.redisDbAccessKeys}"
            - name: REDIS_DB_RESPONSE_KEYS
              value: "${variables.redisDbResponseKeys}"
            - name: REDIS_DB_REVOKED_DEVICES
              value: "${variables.redisDbRevokedDevices}"
            - name: REDIS_DB_HSM_KEYS
              value: "${variables.redisDbHsmKeys}"
            - name: APP_ENV
              value: "dev"
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
  name: app-rb-rolling-restart
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
              kubectl rollout restart deployment app-rb -n ${environment.namespace}

---

apiVersion: v1
kind: Service
metadata:
  name: app-rb
  labels:
    app: app-rb
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
      name: http
  selector:
    app: app-rb

---

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-rb
  labels:
    app: app-rb
spec:
  ingressClassName: nginx
  rules:
    - host: app-rb.better-auth.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-rb
                port:
                  number: 80
