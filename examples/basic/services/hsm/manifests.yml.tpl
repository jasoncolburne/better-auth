apiVersion: apps/v1
kind: Deployment
metadata:
  name: hsm
  labels:
    app: hsm
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hsm
  template:
    metadata:
      labels:
        app: hsm
    spec:
      containers:
        - name: hsm
          image: ${actions.build.hsm.outputs.deployment-image-id}
          ports:
            - containerPort: 11111
              name: http
          env:
            - name: PORT
              value: "11111"
          livenessProbe:
            httpGet:
              path: /health
              port: 11111
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 11111
            initialDelaySeconds: 5
            periodSeconds: 5
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi

---

apiVersion: v1
kind: Service
metadata:
  name: hsm
  labels:
    app: hsm
spec:
  type: ClusterIP
  ports:
    - port: 11111
      targetPort: 11111
      protocol: TCP
      name: http
  selector:
    app: hsm
