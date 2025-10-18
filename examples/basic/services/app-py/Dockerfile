# Multi-stage build for Python app server
# Force rebuild: 2025-10-18-v3
FROM python:3.12-bookworm AS builder

WORKDIR /app

RUN mkdir /dependencies
# Copy the local better-auth-py implementation
COPY implementations/better-auth-py /dependencies/better-auth-py

# Install better-auth-py dependencies first
WORKDIR /dependencies/better-auth-py
RUN pip install --no-cache-dir -e .

# Copy app requirements and install
WORKDIR /app
COPY examples/basic/services/app-py/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY examples/basic/services/app-py/ .

# Final stage
FROM python:3.12-slim-bookworm

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Python packages from builder
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy better-auth-py implementation (needed for -e install)
COPY --from=builder /dependencies/better-auth-py /dependencies/better-auth-py

# Copy application code
COPY --from=builder /app /app

EXPOSE 80

CMD ["python", "server.py"]
