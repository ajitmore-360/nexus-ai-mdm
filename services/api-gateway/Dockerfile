# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: Build
# ─────────────────────────────────────────────────────────────────────────────
FROM rust:1.88-slim-bookworm AS builder

# Install build-time OS dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev cmake ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY Cargo.toml Cargo.lock ./
COPY shared/   shared/
COPY services/ services/
COPY tools/    tools/

RUN cargo build --release -p api-gateway

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: Minimal runtime image (non-root, no shell, no build tools)
# ─────────────────────────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create a dedicated non-root user — principle of least privilege
RUN groupadd --gid 10001 azile \
 && useradd  --uid 10001 --gid azile --no-create-home --shell /usr/sbin/nologin azile

COPY --from=builder /workspace/target/release/api-gateway /usr/local/bin/api-gateway

# Ensure binary is owned by root but executable by azile user
RUN chown root:azile /usr/local/bin/api-gateway \
 && chmod 550 /usr/local/bin/api-gateway

USER azile

EXPOSE 8080

# Health check so orchestrators can detect unhealthy containers
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -sf http://localhost:8080/health || exit 1

ENTRYPOINT ["/usr/local/bin/api-gateway"]
