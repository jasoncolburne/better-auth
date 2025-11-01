# Multi-stage build for Ruby app server
FROM ruby:3.4-bookworm AS builder

# Install build dependencies for native extensions
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /dependencies/better-auth-rb

# Copy the local better-auth-rb implementation
COPY implementations/better-auth-rb .

# Build and install the gem in the builder
RUN gem update bundler && \
    bundle install --without development test && \
    gem build better_auth.gemspec && \
    gem install better_auth-*.gem

# Install app dependencies in the builder
WORKDIR /app
COPY examples/garden-k8s/services/app-rb/Gemfile examples/garden-k8s/services/app-rb/Gemfile.lock* ./
RUN bundle install --jobs 4 --retry 3

# Copy application code
COPY examples/garden-k8s/services/app-rb/ .

# Inject HSM identity from test-fixtures/hsm.id
COPY examples/garden-k8s/test-fixtures/hsm.id /tmp/hsm.id
RUN HSM_ID=$(cat /tmp/hsm.id) && \
    sed -i "s/BETTER_AUTH_HSM_IDENTITY_PLACEHOLDER/$HSM_ID/" lib/storage/key_verifier.rb && \
    rm /tmp/hsm.id

# Final stage
FROM ruby:3.4-slim-bookworm

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy installed gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application code
COPY --from=builder /app .

EXPOSE 80

CMD ["bundle", "exec", "puma", "config.ru", "-p", "80"]
