FROM hexpm/elixir:1.18.4-erlang-28.1-debian-bullseye-20250929-slim
ADD mix.exs mix.lock ./
RUN mix deps.get
RUN cp deps/castore/priv/cacerts.pem /
COPY coverage_reporter /
COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
