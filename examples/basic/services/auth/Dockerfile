# Multi-stage build for Go auth server
FROM golang:1.25-bookworm AS builder

WORKDIR /app

RUN mkdir /dependencies
# Copy the local better-auth-go implementation
COPY implementations/better-auth-go /dependencies/better-auth-go

# Copy go module files
COPY examples/basic/services/auth/go.mod examples/basic/services/auth/go.sum ./
RUN go mod download

# Copy source code
COPY examples/basic/services/auth/ .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o auth .

# Final stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /root/

COPY --from=builder /app/auth .

EXPOSE 80

CMD ["./auth"]
