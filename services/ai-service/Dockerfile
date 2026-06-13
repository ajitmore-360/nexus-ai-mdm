FROM rust:1.88-slim-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends pkg-config libssl-dev cmake ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
COPY Cargo.toml Cargo.lock ./
COPY shared/ shared/
COPY services/ services/
COPY tools/ tools/
RUN cargo build --release -p ai-service

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libssl3 curl && rm -rf /var/lib/apt/lists/* && apt-get clean
RUN groupadd --gid 10001 nexus && useradd --uid 10001 --gid nexus --no-create-home --shell /usr/sbin/nologin nexus
COPY --from=builder /workspace/target/release/ai-service /usr/local/bin/ai-service
RUN chown root:nexus /usr/local/bin/ai-service && chmod 550 /usr/local/bin/ai-service
USER nexus
EXPOSE 8082
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 CMD curl -sf http://localhost:8082/health || exit 1
ENTRYPOINT ["/usr/local/bin/ai-service"]
