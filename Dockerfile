# Stage 1: Build native modules
FROM node:24-alpine AS builder

WORKDIR /app

# Install build dependencies for native modules (bcrypt, sqlite3)
RUN apk add --no-cache python3 make g++

# Install app dependencies
COPY package*.json ./
RUN npm ci --omit=dev

# Stage 2: Runtime image (no build tools)
FROM node:24-alpine

WORKDIR /app

# Copy installed node_modules from builder
COPY --from=builder /app/node_modules ./node_modules

# Bundle app source
COPY package*.json ./
COPY . .

# Define build argument for version
ARG VERSION=development
ENV APP_VERSION=$VERSION

# OCI image labels — FHIRTX customization of FHIRsmith.
# Upstream attribution is retained via `org.opencontainers.image.source`
# (the fork) and the file-level copyright headers inside the image.
LABEL org.opencontainers.image.title="FHIRTX (FHIRsmith)" \
      org.opencontainers.image.description="FHIRTX-branded FHIR terminology server, built on FHIRsmith." \
      org.opencontainers.image.vendor="FHIRTX" \
      org.opencontainers.image.authors="Benjamin Arfa <benjamin.arfa.pro@gmail.com>" \
      org.opencontainers.image.source="https://github.com/benjamin-arfa/FHIRsmith" \
      org.opencontainers.image.licenses="BSD-3-Clause" \
      org.opencontainers.image.version="${VERSION}"

# Expose port and define command
EXPOSE 3000
CMD ["node", "server.js"]