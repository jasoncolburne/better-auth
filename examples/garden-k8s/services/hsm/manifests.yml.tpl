apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: softhsm-tokens
  labels:
    app: hsm
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 128Mi

---

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
      initContainers:
        - name: init-softhsm
          image: ${actions.build.hsm.outputs.deployment-image-id}
          command:
            - /bin/sh
            - -c
            - |
              if [ ! -d "/var/lib/softhsm/tokens" ] || [ -z "$(ls -A /var/lib/softhsm/tokens)" ]; then
                echo "Initializing SoftHSM2 token..."
                softhsm2-util --init-token --slot 0 --label "test-token" --so-pin "5678" --pin "1234"
                echo "Token initialized successfully"
              else
                echo "Token already exists, skipping initialization"
              fi
          volumeMounts:
            - name: softhsm-tokens
              mountPath: /var/lib/softhsm/tokens
      containers:
        - name: hsm
          image: ${actions.build.hsm.outputs.deployment-image-id}
          ports:
            - containerPort: ${variables.hsmPort}
              name: http
          env:
            - name: PORT
              value: "${variables.hsmPort}"
            - name: REDIS_HOST
              value: "${variables.redisHost}:${variables.redisPort}"
            - name: REDIS_DB_HSM_KEYS
              value: "${variables.redisDbHsmKeys}"
            - name: POSTGRES_HOST
              value: "${variables.postgresHost}"
            - name: POSTGRES_PORT
              value: "${variables.postgresPort}"
            - name: POSTGRES_DATABASE
              value: "${variables.postgresDbHsm}"
            - name: POSTGRES_USER
              value: "${variables.postgresUser}"
            - name: POSTGRES_PASSWORD
              value: "${variables.postgresPassword}"
          livenessProbe:
            httpGet:
              path: /health
              port: ${variables.hsmPort}
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: ${variables.hsmPort}
            initialDelaySeconds: 5
            periodSeconds: 5
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
          volumeMounts:
            - name: softhsm-tokens
              mountPath: /var/lib/softhsm/tokens
      volumes:
        - name: softhsm-tokens
          persistentVolumeClaim:
            claimName: softhsm-tokens

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
    - port: ${variables.hsmPort}
      targetPort: ${variables.hsmPort}
      protocol: TCP
      name: http
  selector:
    app: hsm
