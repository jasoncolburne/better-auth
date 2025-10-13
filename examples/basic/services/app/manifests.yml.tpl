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
            - containerPort: 3000
              name: http
          env:
            - name: PORT
              value: "3000"
            - name: AUTH_SERVER_URL
              value: "http://auth:8080"
            - name: REDIS_HOST
              value: "redis:6379"
            - name: NODE_ENV
              value: "production"
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
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
  name: app
  labels:
    app: app
spec:
  type: ClusterIP
  ports:
    - port: 3000
      targetPort: 3000
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
                  number: 3000
