#!/usr/bin/sh

usage()
{
    echo "Usage:"
    echo "    $0 <options>"
    echo "    autossh                           Initialize autossh between cluster nodes."
    echo "    install [manager|monitor]         Default, install all components that kafka depends on. Only install manager|monitor if it's specified."
    echo "    uninstall [manager|monitor]       Default, remove all components that kafka depends on. Only uninstall manager|monitor if it's specified."
    echo "    start [manager|monitor]           Default, start all relevant service in the cluster. Only start manager|monitor if it's specified."
    echo "    stop [manager|monitor]            Default, stop all relevant service in the cluster. Only stop manager|monitor if it's specified."
}

error_check()
{
    if [ "$?" != "0" ]; then
        echo "$1 failed, check it pls!"
        exit 1
    fi
}

install_jre()
{
    echo "Prepare to install jre ..."

    tar -zxf $jre_tarball > /dev/null

    for host in $cluster_nodes
    do
        scp -r $work_dir/jre1.8.0_111 root@$host:$home_dir > /dev/null
        ssh $host "echo export PATH=$home_dir/jre1.8.0_111/bin:$PATH >> /etc/profile"
        ssh $host "echo JAVA_HOME=$home_dir/jre1.8.0_111 >> /etc/profile"
    done

    echo "Install jre over."
}

install_zk()
{
    echo "Prepare to install zookeeper ..."

    tar -zxf $zk_tarball
    cp $work_dir/zookeeper-3.4.6/conf/zoo_sample.cfg $work_dir/zookeeper-3.4.6/conf/zoo.cfg
    sed -i "12cdataDir=/var/lib/zookeeper" $work_dir/zookeeper-3.4.6/conf/zoo.cfg

    myid=1
    for host in $zk_nodes
    do 
        scp -r $work_dir/zookeeper-3.4.6 root@$host:$home_dir > /dev/null

        idx=1
        for node in $zk_nodes
        do
            if [ "$node" == "$host" ]; then
                ssh $host "echo server.$idx=0.0.0.0:2888:3888 >> $home_dir/zookeeper-3.4.6/conf/zoo.cfg"
            else
                ssh $host "echo server.$idx=$node:2888:3888 >> $home_dir/zookeeper-3.4.6/conf/zoo.cfg"
            fi
            idx=`expr $idx + 1`
        done

        ssh $host "mkdir -p /var/lib/zookeeper"
        ssh $host "echo $myid > /var/lib/zookeeper/myid"
        myid=`expr $myid + 1`
    done

    rm -rf $work_dir/zookeeper-3.4.6/
    start_zookeeper

    echo "Install zookeeper over."
}

install_kafka()
{
    echo "Prepare to install kafka ..."

    tar -zxf $kafka_tarball > /dev/null

    zkconnect=""
    for node in $zk_nodes
    do
        zkconnect+=$node:2181,
    done

    sed -i 60clog.dirs=/var/lib/kafka-logs $work_dir/kafka_2.10-0.9.0.1/config/server.properties
    sed -i 39cadvertised.port=9092 $work_dir/kafka_2.10-0.9.0.1/config/server.properties
    sed -i "116czookeeper.connect=${zkconnect%,*}" $work_dir/kafka_2.10-0.9.0.1/config/server.properties
    echo delete.topic.enable=true >> $work_dir/kafka_2.10-0.9.0.1/config/server.properties

    idx=1
    for host in $kafka_nodes
    do
        scp -r $work_dir/kafka_2.10-0.9.0.1 root@$host:$home_dir >/dev/null
        ssh $host "sed -i 20cbroker.id=$idx $home_dir/kafka_2.10-0.9.0.1/config/server.properties"
        ssh $host "sed -i 35cadvertised.host.name=$host $home_dir/kafka_2.10-0.9.0.1/config/server.properties"
        ssh $host "sed -i 30chost=$host $home_dir/kafka_2.10-0.9.0.1/config/server.properties"
        idx=`expr $idx + 1`
    done

    rm -rf $work_dir/kafka_2.10-0.9.0.1/
    start_kafka

    echo "Install kafka over."
}

install_manager()
{
    echo "Prepare to install kafka-manager ..."

    tar -zxf $manager_tarball > /dev/null
    sed -i 23c'kafka-manager.zkhosts'=\"$manager_zkhost\" $work_dir/kafka-manager-1.3.0.7/conf/application.conf
    mv $work_dir/kafka-manager-1.3.0.7 $home_dir
    chmod +x $home_dir/kafka-manager-1.3.0.7/bin/kafka-manager

    rm -rf $work_dir/kafka-manager-1.3.0.7/
    start_manager

    echo "Install kafka-manager over."
}

install_monitor()
{
    echo "Prepare to install kafka-monitor ..."

    cp $work_dir/KafkaOffsetMonitor-assembly-0.3.0-SNAPSHOT.jar $home_dir
    mkdir -p /var/log/KafkaOffsetMonitor/

    start_monitor

    echo "Install kafka-monitor over."
}

start_manager()
{
    nohup $home_dir/kafka-manager-1.3.0.7/bin/kafka-manager -Dconfig.file=$home_dir/kafka-manager-1.3.0.7/conf/application.conf &
}

start_monitor()
{
    if [[ "$monitor_offsetstorage1" != "" && "$monitor_port1" != "" ]]; then
        nohup java -cp $home_dir/KafkaOffsetMonitor-assembly-0.3.0-SNAPSHOT.jar \
        com.quantifind.kafka.offsetapp.OffsetGetterWeb \
        --offsetStorage $monitor_offsetstorage1 \
        --zk $monitor_zkaddr \
        --port $monitor_port1 \
        --refresh 10.seconds \
        --retain 2.days > /var/log/KafkaOffsetMonitor/KafkaOffsetMonitor.log &
    fi

    if [[ "$monitor_offsetstorage2" != "" && "$monitor_port2" != "" ]]; then
        nohup java -cp $home_dir/KafkaOffsetMonitor-assembly-0.3.0-SNAPSHOT.jar \
        com.quantifind.kafka.offsetapp.OffsetGetterWeb \
        --offsetStorage $monitor_offsetstorage2 \
        --zk $monitor_zkaddr \
        --port $monitor_port2 \
        --refresh 10.seconds \
        --retain 2.days > /var/log/KafkaOffsetMonitor/KafkaOffsetMonitor.log &
    fi
}

uninstall_jre_all()
{
    for host in $cluster_nodes
    do
        ssh $host "sed -i '/jre1.8.0_111/d' /etc/profile"
        ssh $host "rm -rf $home_dir/jre1.8.0_111"
        #ssh $host "source /etc/profile"
    done
}

uninstall_zk_all()
{
    for host in $zk_nodes
    do
        ssh $host "$home_dir/zookeeper-3.4.6/bin/zkServer.sh stop"
        sleep 1
        ssh $host "rm -rf $home_dir/zookeeper-3.4.6/"
    done
}

uninstall_kafka_all()
{
    for host in $kafka_nodes
    do
        ssh $host "$home_dir/kafka_2.10-0.9.0.1/bin/kafka-server-stop.sh"
        sleep 1
        ssh $host "rm -rf $home_dir/kafka_2.10-0.9.0.1/"
    done
}

init_autossh()
{
    if [ -e /root/.ssh/known_hosts ]; then
        >/root/.ssh/known_hosts
    fi

    ssh-keygen
    for host in $cluster_nodes
    do
        echo "Prepare to auto ssh $host ..."
        ssh-copy-id root@$host
        error_check ${FUNCNAME}
    done

    echo "Initialize autossh over."
}

install_all()
{
    for node in $cluster_nodes
    do
        ssh $node "mkdir -p $home_dir"
    done

    if [ ! -d $home_dir/jre1.8.0_111 ]; then
        install_jre
    fi

    if [ $# -lt 1 ]; then
        install_zk
        install_kafka
    elif [ "$1" == "manager" ]; then
        install_manager
    elif [ "$1" == "monitor" ]; then
        install_monitor
    else
        usage
        exit 1
    fi
}

uninstall_all()
{
    if [ $# -lt 1 ]; then
        uninstall_kafka_all
        uninstall_zk_all
        #uninstall_jre_all
        rm -rf $work_dir/kafka_2.10-0.9.0.1/
        rm -rf $work_dir/zookeeper-3.4.6/
        #rm -rf $work_dir/jre1.8.0_111/
    elif [ "$1" == "manager" ]; then
        uninstall_manager
    elif [ "$1" == "monitor" ]; then
        uninstall_monitor
    else
       usage
       exit 1
    fi
}

uninstall_manager()
{
    stop_manager
    sleep 1
    rm -rf $home_dir/kafka-manager-1.3.0.7/
}

uninstall_monitor()
{
    stop_monitor
    sleep 1
    rm -f $home_dir/KafkaOffsetMonitor-assembly-0.3.0-SNAPSHOT.jar
}

stop_manager()
{
    ps -ef | grep -v grep | grep kafka-manager-1.3.0.7 | awk '{print $2}' | xargs kill
}

stop_monitor()
{
    ps -ef | grep KafkaOffsetMonitor-assembly-0.3.0-SNAPSHOT.jar | grep -v grep | awk '{print $2}' | xargs kill
}

start_all()
{
    if [ $# -lt 1 ]; then
        start_zookeeper
        start_kafka
    elif [ "$1" == "manager" ]; then
        start_manager
    elif [ "$1" == "monitor" ]; then
        start_monitor
    else
        usage
        exit 1
    fi
}

start_zookeeper()
{
    for host in $zk_nodes
    do
        ssh $host "$home_dir/zookeeper-3.4.6/bin/zkServer.sh start"
    done
}

start_kafka()
{
    for host in $kafka_nodes
    do
        ssh $host "$home_dir/kafka_2.10-0.9.0.1/bin/kafka-server-start.sh -daemon $home_dir/kafka_2.10-0.9.0.1/config/server.properties"
    done
}

stop_all()
{
    if [ $# -lt 1 ]; then
        stop_kafka
        stop_zookeeper
    elif [ "$1" == "manager" ]; then
        stop_manager
    elif [ "$1" == "monitor" ]; then
        stop_monitor
    else
        usage
        exit 1
    fi
}

stop_zookeeper()
{
    for host in $zk_nodes
    do
        ssh $host "$home_dir/zookeeper-3.4.6/bin/zkServer.sh stop"
    done
}

stop_kafka()
{
    for host in $kafka_nodes
    do
        #ssh $host "ps ax | grep -i 'kafka\.Kafka' | grep java | grep -v grep | awk '{print $1}' | xargs kill -9"
        ssh $host "$home_dir/kafka_2.10-0.9.0.1/bin/kafka-server-stop.sh"
    done
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

work_dir=$PWD
deploy_conf=$work_dir/kafka_deploy.conf
jre_tarball=$work_dir/jre1.8.0_111.tar.gz
zk_tarball=$work_dir/zookeeper-3.4.6.tar.gz
kafka_tarball=$work_dir/kafka_2.10-0.9.0.1.tar.gz
manager_tarball=$work_dir/kafka-manager-1.3.0.7.tar.gz
home_dir=`cat $deploy_conf | grep home_dir | awk -F'=' '{print $2}' | sed 's/ //g'`
kafka_nodes=`cat $deploy_conf | grep kafka_nodes | awk -F'=' '{print $2}' | sed 's/,/ /g'`
zk_nodes=`cat $deploy_conf | grep zk_nodes | awk -F'=' '{print $2}' | sed 's/,/ /g'`
cluster_nodes=`echo $kafka_nodes $zk_nodes | sed 's/ /\n/g' | sort -u | tr -s '\n' ' '`
manager_zkhost=`cat $deploy_conf | grep manager_zkhost | awk -F'=' '{print $2}' | sed 's/ //g'`
monitor_zkaddr=`cat $deploy_conf | grep monitor_zkaddr | awk -F'=' '{print $2}' | sed 's/ //g'`
monitor_offsetstorage1=`cat $deploy_conf | grep monitor_offsetstorage1 | awk -F'=' '{print $2}' | sed 's/ //g'`
monitor_offsetstorage2=`cat $deploy_conf | grep monitor_offsetstorage2 | awk -F'=' '{print $2}' | sed 's/ //g'`
monitor_port1=`cat $deploy_conf | grep monitor_port1 | awk -F'=' '{print $2}' | sed 's/ //g'`
monitor_port2=`cat $deploy_conf | grep monitor_port2 | awk -F'=' '{print $2}' | sed 's/ //g'`
 
case $1 in
    autossh)     init_autossh;;
    install)     if [ $# -eq 1 ]; then
                     install_all
                 elif [ $# -eq 2 ]; then
                     install_all $2
                 else
                     usage
                 fi
                 ;;
    uninstall)   if [ $# -eq 1 ]; then
                     uninstall_all
                 elif [ $# -eq 2 ]; then
                     uninstall_all $2
                 else
                     usage
                 fi
                 ;;
    start)       if [ $# -eq 1 ]; then
                     start_all
                 elif [ $# -eq 2 ]; then
                     start_all $2
                 else
                     usage
                 fi
                 ;;
    stop)        if [ $# -eq 1 ]; then
                     stop_all
                 elif [ $# -eq 2 ]; then
                     stop_all $2
                 else
                     usage
                 fi
                 ;;
    *)           usage;;
esac
