apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  labels:
    app: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      containers:
        - name: app
          image: ${actions.build.app.outputs.deployment-image-id}
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
            - name: NODE_ENV
              value: "production"
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
  name: app-rolling-restart
  namespace: ${environment.namespace}
spec:
  schedule: "0 */12 * * *"
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
              kubectl rollout restart deployment app -n ${environment.namespace}

---

apiVersion: v1
kind: Service
metadata:
  name: app
  labels:
    app: app
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
      name: http
  selector:
    app: app

---

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  labels:
    app: app
spec:
  ingressClassName: nginx
  rules:
    - host: app.better-auth.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app
                port:
                  number: 80
