#!/usr/bin/env bash
set -e
set -o pipefail
echo ">>> Running command"
echo ""
# bash -c "set -e;  set -o pipefail; $1"
cd /app
mix local.hex --force 
mix local.rebar --force
mix deps.get
mix compile
mix run --no-mix-exs -e "CoverageReporter.run()"