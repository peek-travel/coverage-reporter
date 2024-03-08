FROM hexpm/elixir:1.16.1-erlang-26.2.2-ubuntu-jammy-20240125

COPY coverage_reporter /
COPY entrypoint.sh /
COPY deps/castore/priv/cacerts.pem /

ENTRYPOINT ["/entrypoint.sh"]
