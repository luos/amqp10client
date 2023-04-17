#!/bin/bash
set -ex

export RABBITMQ_HOST=3.75.89.183
export RABBITMQ_USERNAME=testuser
export RABBITMQ_PASSWORD=rabbitmq2022

tests=$(ls tests/*)
bash -c "rebar3 compile && rebar3 release"
for t in $tests; do
    test_name=$(basename $t)
    echo "Running $test_name"
    export AMCLIENT_OUT_FILE="$PWD/output/$test_name.out"
    source $t
    ./_build/default/rel/amclient/bin/amclient foreground || true
    sleep 45
done
