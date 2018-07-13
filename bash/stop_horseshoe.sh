#!/usr/bin/env bash

for p in 43306 33306 23306 13306; do
    mysqladmin -h 127.0.0.1 -P${p} shutdown;
done

# shellcheck disable=SC2034
for i in {1..60}; do 
    if [ "$(docker ps | wc -l)" -eq 1 ]; then
        break;
    fi;
    sleep 1;
done

if [ "$(docker ps | wc -l)" -ne 1 ]; then
    exit 1;
fi

