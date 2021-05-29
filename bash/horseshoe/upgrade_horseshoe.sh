#!/usr/bin/env bash

# Stop/remove any running mysql containers
./stop_horseshoe.sh
for c in $(docker ps -a | awk '{print $NF}' | grep -P 'mysql[0-9]+'); do
    docker rm "${c}";
done

# Delete any mysql images
for i in $(docker images | grep mysql | awk '{print $3}' | sort | uniq); do
    docker rmi -f "${i}";
done

docker pull mysql:latest
./make_horseshoe.sh

for c in $(docker ps -a | awk '{print $NF}' | grep -P 'mysql[0-9]+'); do
    # shellcheck disable=SC2016
    docker exec -it "${c}" bash -c 'mysql_upgrade -u root -p${MYSQL_ROOT_PASSWORD}';
done

