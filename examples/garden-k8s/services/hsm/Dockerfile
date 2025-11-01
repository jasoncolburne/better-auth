# Multi-stage build for SoftHSM2 service
FROM golang:1.25.1-bookworm AS builder

WORKDIR /app

# Copy go module files
COPY examples/garden-k8s/services/hsm/go.mod examples/garden-k8s/services/hsm/go.sum ./
RUN go mod download

# Copy source code
COPY examples/garden-k8s/services/hsm/*.go ./

# Build the HSM server
RUN CGO_ENABLED=1 GOOS=linux go build -o hsm-server .

# Final stage
FROM debian:bookworm-slim

# Install SoftHSM2, PKCS#11 tools, OpenSSL, curl, and jq
RUN apt-get update && apt-get install -y \
    softhsm2 \
    opensc \
    openssl \
    ca-certificates \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy HSM server binary from builder
COPY --from=builder /app/hsm-server .

EXPOSE 11111

# Start the HSM server
CMD ["./hsm-server"]
