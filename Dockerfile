ARG ELIXIR_VERSION=1.14.4
ARG OTP_VERSION=25.3.1
ARG DEBIAN_VERSION=bullseye-20230227-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app
COPY mix.exs mix.lock entrypoint.sh ./
COPY lib ./lib

ENTRYPOINT ["/app/entrypoint.sh"]