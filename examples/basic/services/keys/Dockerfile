# Multi-stage build for Ruby keys server
FROM ruby:3.3-bookworm AS builder

WORKDIR /app

# Copy Gemfile and install dependencies
COPY examples/basic/services/keys/Gemfile examples/basic/services/keys/Gemfile.lock* ./
RUN bundle install --jobs 4 --retry 3

# Copy application code
COPY examples/basic/services/keys/ .

# Final stage
FROM ruby:3.3-slim-bookworm

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application code
COPY --from=builder /app /app

EXPOSE 80

CMD ["bundle", "exec", "puma", "config.ru", "-p", "80"]
