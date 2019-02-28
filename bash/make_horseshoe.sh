#!/usr/bin/env bash

myip=$(hostname -I | awk '{print $1}')
for port in 13306 23306 33306 43306; do
    rootdir="/data/docker"
    instance="${port:0:1}"
    container="mysql${instance}"
    mysqlx_port=$((port+1))

    # Make the directories.
    sudo mkdir -p "${rootdir}"/"${container}"/conf.d "${rootdir}"/"${container}"/data "${rootdir}"/"${container}"/run
    sudo chown -R vboxadd:vboxsf ${rootdir}/${container}

    # Create the config file.
    sudo bash -c "cat << EOF > ${rootdir}/${container}/conf.d/my.cnf
[mysqld]
server-id = ${instance}
port = ${port}
mysqlx_port = ${mysqlx_port}
binlog_format = ROW
log_bin
log_slave_updates
gtid_mode = ON
enforce_gtid_consistency = true
log_timestamps = system
report_host = ${container}
report_port = ${port}
default_authentication_plugin = mysql_native_password
secure_file_priv = ''
log_bin_trust_function_creators = 1
EOF"

    # Make slaves read-only by default.
    if [ "${instance}" -ne 1 ]; then
        sudo bash -c "echo \"read_only = 1\" >> ${rootdir}/${container}/conf.d/my.cnf"
    fi

    # Start the container.
    docker run --name "${container}" -p "${port}":"${port}" -p "${mysqlx_port}":"${mysqlx_port}" -v "${rootdir}"/"${container}"/conf.d:/etc/mysql/conf.d -v "${rootdir}"/"${container}"/data:/var/lib/mysql -v /tmp:/tmp -v "${rootdir}"/"${container}"/run:/var/run/mysqld -e MYSQL_ROOT_PASSWORD="${MYSQL_PASSWORD}" -e TZ="$(cat /etc/timezone)" -e MYSQL_REPLICATION_USER=replica -e MYSQL_REPLICATION_PASSWORD=replica -e MYSQL_PORT="${port}" -d mysql:8

    can_connect=0
    for i in {1..60}; do
        echo "Connection attempt [${i}]"
        mysql -h "${myip}" -P "${port}" -u root -p"${MYSQL_PASSWORD}" --connect-timeout=1 -e "select 1" 1> /dev/null 2>&1;
        # shellcheck disable=SC2181
        if [ $? -eq 0 ]; then
            can_connect=1
            break
        fi;
        sleep 1;
    done

    if [ "${can_connect}" -eq 0 ]; then
        echo "Failed to create ${container}."
        exit 1
    fi

    # On the master, setup users.
    if [ "${instance}" -eq 1 ]; then

        # User replica.
        mysql -h "${myip}" -P "${port}" -u root -p"${MYSQL_PASSWORD}" -e "create user if not exists 'replica'@'%' identified with mysql_native_password by 'replica' password expire never; grant replication slave on *.* to 'replica'@'%'; flush privileges;" 
        # shellcheck disable=SC2181
        if [ $? -ne 0 ]; then
            echo "$0: Error creating replication user."
            exit 1
        fi

        # User rsmith.
        mysql -h "${myip}" -P "${port}" -u root -p"${MYSQL_PASSWORD}" -e "create user if not exists 'rsmith'@'%' identified with mysql_native_password by '${MYSQL_PASSWORD}' password expire never; grant all privileges on *.* to 'rsmith'@'%' with grant option; flush privileges;"
        # shellcheck disable=SC2181
        if [ $? -ne 0 ]; then
            echo "$0: Error creating rsmith user."
            exit 1
        fi

        # Create the rsmith database.
        mysql -h "${myip}" -P13306 -u rsmith -p"${MYSQL_PASSWORD}" -e "create database if not exists rsmith"
        # shellcheck disable=SC2181
        if [ $? -ne 0 ]; then
            echo "$0: Error creating rsmith database."
            exit 1
        fi

        # Create the steam database.
        mysql -h "${myip}" -P13306 -u rsmith -p"${MYSQL_PASSWORD}" -e "create database if not exists steam"
        # shellcheck disable=SC2181
        if [ $? -ne 0 ]; then
            echo "$0: Error creating steam database."
            exit 1
        fi

    else
        # Instance 1 is the master of instances 2 and 3.
        # Instance 2 is the master of instance 4.
        master_instance=1
        if [ "${instance}" -eq 4 ]; then
            master_instance=3
        fi
        master_container="mysql${master_instance}"

        ./make_docker_gtid_slave.sh "${master_container}" "${container}"
        # shellcheck disable=SC2181
        if [ $? -ne 0 ]; then
            echo "$0: Error setting up replication."
            exit 1
        fi
    fi

done

# Setup master-master between 1 and 3.
mysql -h "${myip}" -P 13306 -u root -p"${MYSQL_PASSWORD}" -e "stop slave; reset slave all; change master to master_host='${myip}', master_port=33306, master_user='replica', master_password='replica', master_auto_position=1; start slave;"
# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    echo "$0: Error setting up replication between 13306 and 33306."
    exit 1
fi
