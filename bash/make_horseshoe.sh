#!/bin/bash

myip=$(hostname -I | awk '{print $1}')
for port in 13306 23306 33306 43306; do
    rdir="/data/docker"
    inum="${port:0:1}"
    cname="mysql${inum}"

    # Make the directories.
    sudo mkdir -p "${rdir}"/"${cname}"/conf.d "${rdir}"/"${cname}"/data "${rdir}"/"${cname}"/run
    sudo chown -R vboxadd:vboxsf ${rdir}/${cname}

    # Create the config file.
    sudo bash -c 'cat << EOF > "${rdir}"/"${cname}"/conf.d/my.cnf
[mysqld]
server-id = "${inum}"
port = "${port}"
binlog_format = ROW
log_bin
log_slave_updates
gtid_mode = ON
enforce_gtid_consistency = true
log_timestamps = system
EOF'

    # Make slaves read-only.
    if [ "${inum}" -ne 1 ]; then
        sudo bash -c 'echo "read_only = 1" >> "${rdir}"/"${cname}"/conf.d/my.cnf'
    fi

    # Start the container.
    docker run --name "${cname}" -p "${port}":"${port}" -v "${rdir}"/"${cname}"/conf:/etc/mysql/conf.d -v "${rdir}"/"${cname}"/data:/var/lib/mysql -v /tmp:/tmp -v "${rdir}"/"${cname}"/run:/var/run/mysqld -e MYSQL_ROOT_PASSWORD="${MYSQL_PASSWORD}" -e TZ="$(cat /etc/timezone)" -e MYSQL_REPLICATION_USER=replica MYSQL_REPLICATION_PASSWORD=replica -d mysql:8

    # Give the container up to 1 minute to start.
    # The init process starts and stops mysql a couple of times. 
    signal=SIGINT 60 docker logs -f "${cname}" | sed '$!d' | grep -qei "ready for connections"
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        (>&2 echo "Failed to start ${cname}")
        exit 1
    fi
    sleep 2
    signal=SIGINT 60 docker logs -f "${cname}" | sed '$!d' | grep -qei "ready for connections"
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        (>&2 echo "Failed to start ${cname}")
        exit 1
    fi

    # On the master, setup replication user.
    if [ "${inum}" -eq 1 ]; then
        mysql -h "${myip}" -P "${port}" -u root -p"${MYSQL_PASSWORD}" -e "create user if not exists 'replica'@'%' identified with mysql_native_password by 'replica' password expire never; grant replication slave on *.* to 'replica'@'%'; flush privileges;" 
        # shellcheck disable=SC2181
        if [ $? -ne 0 ]; then
            echo "$0: Error creating replication user."
            exit 1
        fi
    else
        # Instance 1 is the master of instances 2 and 3.
        # Instance 2 is the master of instance 4.
        minum=1
        if [ "${inum}" -eq 4 ]; then
            minum=2
        fi
        cmaster="mysql${minum}"

        ./make_docker_gtid_slave.sh "${cmaster}" "${cname}"
        # shellcheck disable=SC2181
        if [ $? -ne 0 ]; then
            echo "$0: Error setting up replication."
            exit 1
        fi
    fi

done

# Setup master-master between 1 and 2.
mysql -h "${myip}" -P 13306 -u root -p"${MYSQL_PASSWORD}" -e "stop slave; reset slave all; change master to master_host='${myip}', master_port=23306, master_user='replica', master_password='replica', master_auto_position=1; start slave;"

# Create the rsmith user on the master.
mysql -h "${myip}" -P 13306 -u root -p"${MYSQL_PASSWORD}" -e "create user if not exists 'rsmith'@'%' identified with mysql_native_password by '${MYSQL_PASSWORD}' password expire never; grant all privileges on *.* to 'rsmith'@'%' with grant option; flush privileges;"

# Create the rsmith database.
mysql -h "${myip}" -P13306 -u rsmith -p"${MYSQL_PASSWORD}" -e "create database if not exists rsmith"


