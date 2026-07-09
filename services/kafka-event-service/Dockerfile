FROM rust:1.88-slim-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates gcc g++ make cmake libcurl4-openssl-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
COPY Cargo.toml Cargo.lock ./
COPY shared/ shared/
COPY services/ services/
COPY tools/ tools/
RUN cargo build --release -p kafka-event-service

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libssl3 curl && rm -rf /var/lib/apt/lists/* && apt-get clean
RUN groupadd --gid 10001 azile && useradd --uid 10001 --gid azile --no-create-home --shell /usr/sbin/nologin azile
COPY --from=builder /workspace/target/release/kafka-event-service /usr/local/bin/kafka-event-service
RUN chown root:azile /usr/local/bin/kafka-event-service && chmod 550 /usr/local/bin/kafka-event-service
USER azile
HEALTHCHECK NONE
ENTRYPOINT ["/usr/local/bin/kafka-event-service"]
