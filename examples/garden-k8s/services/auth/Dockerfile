# Multi-stage build for Go auth server
FROM golang:1.25-bookworm AS builder

WORKDIR /app

RUN mkdir /dependencies
# Copy the local better-auth-go implementation
COPY implementations/better-auth-go /dependencies/better-auth-go

# Copy go module files
COPY examples/garden-k8s/services/auth/go.mod examples/garden-k8s/services/auth/go.sum ./
RUN go mod download

# Copy source code
COPY examples/garden-k8s/services/auth/ .

# Inject HSM identity from test-fixtures/hsm.id
COPY examples/garden-k8s/test-fixtures/hsm.id /tmp/hsm.id
RUN HSM_ID=$(cat /tmp/hsm.id) && \
    sed -i "s/BETTER_AUTH_HSM_IDENTITY_PLACEHOLDER/$HSM_ID/" pkg/implementation/accessverificationkeystore.go && \
    rm /tmp/hsm.id

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o auth .

# Final stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /root/

COPY --from=builder /app/auth .

EXPOSE 80

CMD ["./auth"]
