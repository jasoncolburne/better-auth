apiVersion: apps/v1
kind: Deployment
metadata:
  name: keys
  labels:
    app: keys
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keys
  template:
    metadata:
      labels:
        app: keys
    spec:
      containers:
        - name: keys
          image: ${actions.build.keys.outputs.deployment-image-id}
          ports:
            - containerPort: 80
              name: http
          env:
            - name: REDIS_HOST
              value: "${variables.redisHost}:${variables.redisPort}"
            - name: REDIS_DB_RESPONSE_KEYS
              value: "${variables.redisDbResponseKeys}"
            - name: REDIS_DB_HSM_KEYS
              value: "${variables.redisDbHsmKeys}"
            - name: APP_ENV
              value: "dev"
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

apiVersion: v1
kind: Service
metadata:
  name: keys
  labels:
    app: keys
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
      name: http
  selector:
    app: keys

---

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keys
  labels:
    app: keys
spec:
  ingressClassName: nginx
  rules:
    - host: keys.better-auth.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: keys
                port:
                  number: 80
