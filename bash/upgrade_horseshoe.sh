#!/usr/bin/env bash

docker pull mysql:latest
./stop_horseshoe.sh
for c in $(docker ps -a | awk '{print $NF}' | grep -P 'mysql[0-9]+'); do
    docker rm "${c}";
done
./make_horseshoe.sh

for c in $(docker ps -a | awk '{print $NF}' | grep -P 'mysql[0-9]+'); do
    # shellcheck disable=SC2016
    docker exec -it "${c}" bash -c 'mysql_upgrade -u root -p${MYSQL_ROOT_PASSWORD}';
done

