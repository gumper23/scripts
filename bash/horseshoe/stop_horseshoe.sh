#!/usr/bin/env bash

for c in $(docker ps | tail -n+2 | awk '{print $NF}' | grep -P 'mysql[0-9]+'); do
    p=$(docker inspect "${c}" | grep MYSQL_PORT | grep -o '[0-9]*');
    mysqladmin -h 127.0.0.1 -P"${p}" shutdown;
done

# shellcheck disable=SC2034
for i in {1..60}; do 
    if [ "$(docker ps | tail -n+2 | awk '{print $NF}' | grep -c -P 'mysql[0-9]+')" -eq 0 ]; then
        break;
    fi; 
    sleep 1;
done

if [ "$(docker ps | tail -n+2 | awk '{print $NF}' | grep -c -P 'mysql[0-9]+')" -ne 0 ]; then
    echo "Unable to stop all containers";
    exit 1;
fi


