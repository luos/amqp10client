#!/bin/bash
set -ex

export RABBITMQ_HOST=ip-172-31-22-77
export RABBITMQ_USERNAME=testuser
export RABBITMQ_PASSWORD=rabbitmq2022

tests=$(ls tests/*)
for t in "${tests[@]}"; do
    test_name=$(basename $t)
    echo "Running $test_name"
    export AMCLIENT_OUT_FILE="$PWD/output/$test_name.out"
    source $t
    bash -c "rebar3 compile && rebar3 release"
    ./_build/default/rel/amclient/bin/amclient foreground || true
done
