#!/usr/bin/env bash

for i in {1..4}; 
do
    c=mysql${i};
    docker start "${c}" 1>/dev/null 2>&1; 

    can_connect=0; 
    # shellcheck disable=SC2034
    for j in {1..60}; do
        mysql -h 127.0.0.1 -P${i}3306 --connect-timeout=1 -e "select 1" 1> /dev/null 2>&1;
        # shellcheck disable=SC2181
        if [ $? -eq 0 ]; then
            can_connect=1;
            break;
        fi;
        sleep 1;
    done;
    if [ "${can_connect}" -eq 0 ]; then
        echo "Failed to connect to container ${c}";
        exit 1;
    fi;

done

for p in 43306 33306 23306 13306; 
do
    mysql -h 127.0.0.1 -P${p} -e "stop slave; start slave;";
    if [ $? -eq 1 ]; then
        exit 1;
    fi;
done

