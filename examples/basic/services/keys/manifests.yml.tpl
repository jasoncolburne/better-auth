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
            - containerPort: 8081
              name: http
          env:
            - name: PORT
              value: "8081"
            - name: REDIS_HOST
              value: "redis:6379"
            - name: APP_ENV
              value: "dev"
          livenessProbe:
            httpGet:
              path: /health
              port: 8081
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 8081
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
    - port: 8081
      targetPort: 8081
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
                  number: 8081
