# Multi-stage build for Rust application server
# Use latest stable Rust for edition 2024 support
FROM rust:latest AS builder

WORKDIR /app

# Create dependencies directory
RUN mkdir -p /dependencies

# Copy the local better-auth-rs implementation
COPY implementations/better-auth-rs /dependencies/better-auth-rs

# Copy app files
WORKDIR /app
COPY examples/basic/services/app-rs/Cargo.toml ./
COPY examples/basic/services/app-rs/Cargo.lock ./
COPY examples/basic/services/app-rs/src ./src

# Build the application in release mode
RUN cargo build --release

# Final stage
FROM debian:bookworm-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Copy built binary
COPY --from=builder /app/target/release/better-auth-app-rs /app/better-auth-app-rs

EXPOSE 80

CMD ["/app/better-auth-app-rs"]
