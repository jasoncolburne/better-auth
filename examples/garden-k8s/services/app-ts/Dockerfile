# Multi-stage build for TypeScript application server
FROM node:24-bookworm AS builder

WORKDIR /app

RUN mkdir /dependencies
# Copy the local better-auth-ts implementation
COPY implementations/better-auth-ts /dependencies/better-auth-ts

# Install dependencies in the library first
WORKDIR /dependencies/better-auth-ts
RUN npm install && npm run build:tsc

# Copy app files
WORKDIR /app
COPY examples/basic/services/app-ts/package*.json ./
COPY examples/basic/services/app-ts/tsconfig.json ./

# Install dependencies (will use local better-auth-ts via file: reference)
RUN npm install --install-links

# Copy source code
COPY examples/basic/services/app-ts/src ./src

# Inject HSM identity from test-fixtures/hsm.id
COPY examples/basic/test-fixtures/hsm.id /tmp/hsm.id
RUN HSM_ID=$(cat /tmp/hsm.id) && \
    sed -i "s/BETTER_AUTH_HSM_IDENTITY_PLACEHOLDER/$HSM_ID/" src/utils/storage/key-verifier.ts && \
    rm /tmp/hsm.id

# Build the application
RUN npm run build

# Final stage
FROM node:24-bookworm-slim

WORKDIR /app

# Copy built application
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./

EXPOSE 80

CMD ["node", "dist/server.js"]
