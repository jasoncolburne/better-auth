# Multi-stage build for SoftHSM2 service
FROM golang:1.25.1-bookworm AS builder

WORKDIR /app

# Copy go module files
COPY examples/basic/services/hsm/go.mod examples/basic/services/hsm/go.sum ./
RUN go mod download

# Copy source code
COPY examples/basic/services/hsm/*.go ./

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

# Copy initialization and export scripts
COPY examples/basic/services/hsm/init-hsm.sh /init-hsm.sh
COPY examples/basic/services/hsm/export-key.sh /export-key.sh
RUN chmod +x /init-hsm.sh /export-key.sh

# Create directory for optional key import
RUN mkdir -p /keys

# Copy test fixture key if it exists (for reproducible environments)
COPY examples/basic/test-fixtures/hsm-authorization-key.pem /keys/hsm-authorization-key.pem

# Initialize HSM on container start
RUN /init-hsm.sh || (cat /tmp/init.log 2>&1 || true; exit 1)

EXPOSE 11111

# Start the HSM server
CMD ["./hsm-server"]
