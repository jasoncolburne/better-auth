# Multi-stage build for Python app server
FROM python:3.14-bookworm AS builder

# running a script from web is sketchy, so probably download a static copy for a prod deployment
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

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
RUN . "$HOME/.cargo/env" && pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY examples/basic/services/app-py/ .

# Inject HSM identity from test-fixtures/hsm.id
COPY examples/basic/test-fixtures/hsm.id /tmp/hsm.id
RUN HSM_ID=$(cat /tmp/hsm.id) && \
    sed -i "s/BETTER_AUTH_HSM_IDENTITY_PLACEHOLDER/$HSM_ID/" key_verifier.py && \
    rm /tmp/hsm.id

# Final stage
FROM python:3.14-slim-bookworm

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Python packages from builder
COPY --from=builder /usr/local/lib/python3.14/site-packages /usr/local/lib/python3.14/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy better-auth-py implementation (needed for -e install)
COPY --from=builder /dependencies/better-auth-py /dependencies/better-auth-py

# Copy application code
COPY --from=builder /app /app

EXPOSE 80

CMD ["python", "server.py"]
