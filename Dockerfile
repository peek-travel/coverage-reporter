FROM hexpm/elixir:1.16.1-erlang-26.2.2-ubuntu-jammy-20240125
ADD mix.exs mix.lock ./
RUN mix deps.get
RUN cp deps/castore/priv/cacerts.pem /
COPY coverage_reporter /
COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
