#! /bin/bash

make_gtid_slave() {
    local master=${1}
    local slave=${2}

    if [ -z ${master} ] || [ -z ${slave} ]; then
        echo "Usage: make_gtid_slave master_container_name slave_container_name"
        exit 1
    fi
    echo "Making [${slave}] a slave of [${master}]"

    local mpass=$(docker exec ${master} bash -c 'echo $MYSQL_ROOT_PASSWORD')
    if [ -z ${mpass} ]; then
        echo "$0: Unable to get password from ${master}. Is the container running?"
        exit 1
    fi
    echo "master password = [${mpass}]"

    local spass=$(docker exec ${slave} bash -c 'echo $MYSQL_ROOT_PASSWORD')
    if [ -z ${spass} ]; then
        echo "$0: Unable to get password from ${slave}. Is the container running?"
        exit 1
    fi
    echo "slave password = [${spass}]"

    local myip=$(get_ip_addr)
    echo "my ip address = [${myip}]"

    local mport=$(docker inspect ${master} -f '{{(index (index .HostConfig.PortBindings "3306/tcp") 0).HostPort}}')
    echo "master mysql port = [${mport}]"

    local sport=$(docker inspect ${slave} -f '{{(index (index .HostConfig.PortBindings "3306/tcp") 0).HostPort}}')
    echo "slave mysql port = [${sport}]"

    # Stop replication on slave; reset slave.
    mysql -h ${myip} -P ${sport} -u root -p${spass} -e "stop slave; reset slave all; reset master;"

    # Dump all data from master to slave.
    mysqldump -h ${myip} -P ${mport} -u root -p${mpass} --all-databases --events --triggers --routines --single-transaction --set-gtid-purged=on | mysql -h ${myip} -P ${sport} -u root -p${spass}
    if [ $? -ne 0 ]; then
        echo "Error dumping data from [${master}] to [${slave}]"
        exit 1
    fi

    # Setup replication.
    mysql -h ${myip} -P ${sport} -u root -p${mpass} -e "change master to master_host='${myip}', master_port=${mport}, master_user='root', master_password='${mpass}', master_auto_position=1; start slave;"
    if [ $? -ne 0 ]; then
        echo "Error setting up replication on [${slave}]"
        exit 1
    fi

    echo "[${slave}] is now replicating from [${master}]"
}

get_ip_addr() {
    echo $(ip -4 address | grep inet | grep "10\.*" | awk '{print $2}' | sed 's/\/.*//g')
}

if [ $# -ne 2 ]; then
    echo "$0: usage: master_container slave_container"
    exit 1
fi

make_gtid_slave ${1} ${2}

