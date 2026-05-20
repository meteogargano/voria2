ARG ELIXIR_IMAGE="elixir:1.19.5-otp-28-slim"
ARG NODE_IMAGE="node:22-bookworm-slim"
ARG RUNNER_IMAGE="debian:trixie-slim"

FROM ${NODE_IMAGE} AS node

WORKDIR /app

COPY assets/package.json assets/package-lock.json ./assets/
RUN cd assets && npm ci

FROM ${ELIXIR_IMAGE} AS builder

ENV MIX_ENV=prod

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential ca-certificates git curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only ${MIX_ENV}
RUN mix deps.compile

COPY lib lib
COPY priv priv
COPY rel rel
COPY assets assets
COPY --from=node /app/assets/node_modules assets/node_modules

RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM ${RUNNER_IMAGE} AS runner

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV HOME=/app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      libncurses6 \
      libstdc++6 \
      locales \
      openssl && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN useradd --system --create-home --home-dir /app --shell /usr/sbin/nologin app

COPY --from=builder /app/_build/prod/rel/voria2 ./
RUN chown -R app:app /app

USER app

EXPOSE 4000

CMD ["/app/bin/server"]
