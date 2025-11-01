apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-init
  labels:
    app: postgres
data:
  init-databases.sh: |
    #!/bin/bash
    set -e

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
      CREATE DATABASE ${variables.postgresDbAuth};
      CREATE DATABASE ${variables.postgresDbHsm};
    EOSQL

---

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  labels:
    app: postgres
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 256Mi

---

apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  labels:
    app: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          ports:
            - containerPort: ${variables.postgresPort}
              name: postgres
          env:
            - name: POSTGRES_PASSWORD
              value: "${variables.postgresPassword}"
            - name: POSTGRES_USER
              value: "${variables.postgresUser}"
            - name: POSTGRES_DB
              value: "better_auth"
            - name: PGDATA
              value: "/var/lib/postgresql/data/pgdata"
          livenessProbe:
            exec:
              command:
                - pg_isready
                - -U
                - postgres
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
          readinessProbe:
            exec:
              command:
                - pg_isready
                - -U
                - postgres
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 3
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
            - name: postgres-init
              mountPath: /docker-entrypoint-initdb.d
      volumes:
        - name: postgres-data
          persistentVolumeClaim:
            claimName: postgres-data
        - name: postgres-init
          configMap:
            name: postgres-init

---

apiVersion: v1
kind: Service
metadata:
  name: postgres
  labels:
    app: postgres
spec:
  type: ClusterIP
  ports:
    - port: ${variables.postgresPort}
      targetPort: ${variables.postgresPort}
      protocol: TCP
      name: postgres
  selector:
    app: postgres
