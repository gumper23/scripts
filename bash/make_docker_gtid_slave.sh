#!/usr/bin/env bash

make_docker_gtid_slave() {
    local master=${1}
    local slave=${2}

    if [ -z "${master}" ] || [ -z "${slave}" ]; then
        echo "Usage: make_docker_gtid_slave master_container_name slave_container_name"
        exit 1
    fi

    if [ "${master}" = "${slave}" ]; then
        echo "[${master}] is the same container as [${slave}]. Exiting."
        exit 1
    fi

    local replica_user
    # shellcheck disable=SC2016
    replica_user=$(docker exec "${master}" bash -c 'echo $MYSQL_REPLICATION_USER')
    if [ -z "${replica_user}" ]; then
        replica_user="${MYSQL_REPLICATION_USER}"
        if [ -z "${replica_user}" ]; then
            echo "Please set environment variable MYSQL_REPLICATION_USER."
            exit 1
        fi
    fi
    echo "Replication user is [${replica_user}]"

    local replica_password
    # shellcheck disable=SC2016
    replica_password=$(docker exec "${master}" bash -c 'echo $MYSQL_REPLICATION_PASSWORD')
    if [ -z "${replica_password}" ]; then
        replica_password="${MYSQL_REPLICATION_PASSWORD}"
        if [ -z "${replica_password}" ]; then
            echo "Please set environment variable MYSQL_REPLICATION_PASSWORD."
            exit 1
        fi
    fi
    echo "Replication password is [${replica_password}]"

    echo "Making [${slave}] a slave of [${master}]"

    local master_password
    # shellcheck disable=SC2016
    master_password=$(docker exec "${master}" bash -c 'echo $MYSQL_ROOT_PASSWORD')
    if [ -z "${master_password}" ]; then
        echo "$0: Unable to get password from ${master}. Is the container running?"
        exit 1
    fi
    echo "master password = [${master_password}]"

    local slave_password
    # shellcheck disable=SC2016
    slave_password=$(docker exec "${slave}" bash -c 'echo $MYSQL_ROOT_PASSWORD')
    if [ -z "${slave_password}" ]; then
        echo "$0: Unable to get password from ${slave}. Is the container running?"
        exit 1
    fi
    echo "slave password = [${slave_password}]"

    local myip
    myip=$(hostname -I | awk '{print $1}')
    echo "my ip address = [${myip}]"

    local master_port
    # shellcheck disable=SC2016
    master_port=$(docker exec "${master}" bash -c 'echo $MYSQL_PORT')
    echo "master mysql port = [${master_port}]"

    local slave_port
    # shellcheck disable=SC2016
    slave_port=$(docker exec "${slave}" bash -c 'echo $MYSQL_PORT')
    echo "slave mysql port = [${slave_port}]"

    # Stop replication on slave; reset slave.
    mysql -h "${myip}" -P "${slave_port}" -u root -p"${slave_password}" -e "stop slave; reset slave all; reset master;"

    # Dump all data from master to slave.
    mysqldump -h "${myip}" -P "${master_port}" -u root -p"${master_password}" --all-databases --events --triggers --routines --single-transaction --flush-privileges | mysql -h "${myip}" -P "${slave_port}" -u root -p"${slave_password}"
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        echo "Error dumping data from [${master}] to [${slave}]"
        exit 1
    fi

    # Setup replication.
    echo "change master to master_host='${myip}', master_port=${master_port}, master_user='${replica_user}', master_password='${replica_password}', master_auto_position=1; start slave;"
    mysql -h "${myip}" -P "${slave_port}" -u root -p"${master_password}" -e "change master to master_host='${myip}', master_port=${master_port}, master_user='${replica_user}', master_password='${replica_password}', master_auto_position=1; start slave;"
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        echo "Error setting up replication on [${slave}]"
        exit 1
    fi
    sleep 1

    local slave_threads
    slave_threads=$(mysql -h "${myip}" -P "${slave_port}" -u root -p"${master_password}" -e "show slave status\G" | grep -c "Slave_IO_Running: Yes\|Slave_SQL_Running: Yes")
    if [ "${slave_threads}" -ne 2 ]; then
        echo "Error: replication thread(s) not running."
        echo "slave_threads = [${slave_threads}]"
        exit 1
    fi

    echo "[${slave}] is now replicating from [${master}]"
}

if [ $# -ne 2 ]; then
    echo "$0: usage: master_container slave_container"
    exit 1
fi

make_docker_gtid_slave "${1}" "${2}"

