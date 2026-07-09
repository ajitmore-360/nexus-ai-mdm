FROM rust:1.88-slim-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates gcc g++ make cmake libcurl4-openssl-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
COPY Cargo.toml Cargo.lock ./
COPY shared/ shared/
COPY services/ services/
COPY tools/ tools/
RUN cargo build --release -p ingest-service

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libssl3 curl && rm -rf /var/lib/apt/lists/* && apt-get clean
RUN groupadd --gid 10001 azile && useradd --uid 10001 --gid azile --no-create-home --shell /usr/sbin/nologin azile
COPY --from=builder /workspace/target/release/ingest-service /usr/local/bin/ingest-service
RUN chown root:azile /usr/local/bin/ingest-service && chmod 550 /usr/local/bin/ingest-service
USER azile
EXPOSE 8083
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 CMD curl -sf http://localhost:8083/health || exit 1
ENTRYPOINT ["/usr/local/bin/ingest-service"]
