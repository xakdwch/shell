#!/bin/sh
#    Multifunctional script for ceph
#    Version:v0.1

help_info()
{
    echo "Usage:"
    echo "    $0 [OPTIONS]"
    echo ""
    echo "    --help                    [OK]display the help information"
    echo "    initos                    [OK]initialize operating system, start osds when reboot, ntp server, tune kernel parametres, etc."
    echo "    initntp                   initialize ntp service"
    echo "    balancepg {threshold}     rebalance pg, e.g. $0 balancepg 0.02"
    echo "    scheduler                 record cluster performance data regularly, e.g. disk, cpu, top"
    echo "    cluster                   [OK]deploy the ceph cluster"
    echo "    inkscope                  deploy the inkscope"
    echo "    calamari                  [OK]deploy the calamari"
    echo "    start {<service>}         start inkscope, calamari etc"
    echo "    stop {<service>}          stop inkscope, calamari etc"
    echo "    uninstall {<program>}     [OK]destory the program, e.g. $0 uninstall cluster; $0 uninstall inkscope"
    echo "    precheck                  [OK]check the diff between confiuration and cluster, e.g. network, device, package version"
    echo "    daemon                    [OK]monitor the status of osd process and bring up the down osds"
    echo "    createpool {<name>}       [OK]create new replicate|erasure pool for the cluster. e.g. $0 createpool ec"
    echo "    delpool {<name|type>}     [OK]delete the specific pool from the cluster. e.g. $0 delpool all/rbd/rgw/etc."
    echo "    zap {<host:devname>|all}  zap a specific single disk or all disks in the cluster only"
    echo "    autossh                   [OK]init autossh between the cluster nodes only"
    echo "    pushconf                  [OK]push configuration to slave nodes only"
    echo "    pushhosts                 [OK]push the /etc/hosts file to every nodes in the cluster"
    echo "    addmon {host}             add a new monitor to the cluster only"
    echo "    delmon {<host>|all}       delete a specific or all monitors from the cluster only"
    echo "    mountosd {<host>}         [OK]osds' uuid to fstab in the specific host"
    echo "    addosd {host:devname}     add a new osd to the cluster only. e.g. $0 addosd node1:/dev/sdb"
    echo "    delosd {host:osd.num}     delete the specific osd from the cluster only"
    echo "    addrgw {host}             [OK]add a rados gateway to the cluster only"
    echo "    delrgw {host}             [OK]delete the specific rados gateway from the cluster only"
    echo "    listosd                   list all osds' information in the cluster"
    echo "    listpool                  list all pools' information in the cluster"
    echo "    listpg                    list all pgs' information in the cluster"
    echo "    query {<pool|pg|osd>}     query details of pool|pg|osd|etc."
}

usage()
{
    echo "    Try $0 -h for details please."
}

error_check()
{
    if [ "$?" != "0" ]; then
        echo "$1 failed, check it pls!"
        exit 1
    fi
}

clean_dist()
{
    rm -f node*.disk
}

param_check()
{
    echo "nothing to do"
}

start_osds()
{
    if [ $# != 1 ]; then
        echo "Unknown host, please specify a valid host!"
        exit 1
    fi

    host=$1
    ceph-disk activate-all
    #for dev in `cat $script_root/$host.disk`
    #do
    #    disk=`echo $dev | awk -F/ '{print $3}'`
    #    ceph-disk-udev $data_idx $disk$data_idx $disk
    #    ceph-disk-udev $journal_idx $disk$hournal_idx $disk
    #done
}

zap_specific_disk()
{
    if [ $# != 1 ]; then
        echo "Unknown host, please specify a valid host!"
        exit 1
    fi

    host=`echo $1 | awk -F ':' '{print $1}'`
    disk=`echo $1 | awk -F ':' '{print $2}'`

    echo "Show information of $disk in $host:"
    ssh $host "fdisk -l $disk"
    echo "WARNNING: This's a unrecoverabel operation, are you sure to zap $host:$disk? yes/no"
    read answer
    case $answer in
        yes|YES) ;;
        *)       exit 0;;
    esac

    ssh $host mount -l | awk '{print $1}' | grep $disk$data_idx
    if [ "$?" == "0" ]; then
        ssh $host umount $disk$data_idx
        error_check ${FUNCNAME}
    fi  

    echo "============ssh $host mkfs.xfs -f $disk"
    ssh $host mkfs.xfs -f $disk
    #ceph-deploy disk zap $host:$disk
    error_check ${FUNCNAME}
}

create_rgw()
{
    if [ $# != 1 ]; then
        echo "Unknown host, please specify a valid host!"
        exit 1
    fi

    host=$1
    ceph auth get-or-create client.radosgw.gateway$host osd 'allow rwx' mon 'allow rwx' -o /etc/ceph/ceph.client.radosgw$host.keyring

    ceph auth list | grep client.radosgw.gateway$host
    error_check ${FUNCNAME}

    cp -f /etc/ceph/ceph.conf /etc/ceph/ceph.conf.bak
cat >> $cluster_root/ceph.conf << EOF

[client.radosgw.gateway$host]
host = $host
keyring = /etc/ceph/ceph.client.radosgw$host.keyring
rgw_socket_path = /var/run/ceph/ceph-client.radosgw.gateway$host.asok
log_file = /var/log/radosgw/client.radosgw.gateway$host.log
rgw_frontends = civetweb port=81
rgw_print_continue = false
rgw_enable_ops_log = false
rgw_ops_log_rados = false
rgw_ops_log_data_bakclog = 4096
rgw_thread_pool_size = 256
rgw_num_rados_handles = 12
rgw_max_chunk_size = 4194304
EOF
    scp /etc/ceph/ceph.client.radosgw$host.keyring $cluster_user@$host:/etc/ceph
    error_check ${FUNCNAME}
    push_conf
}

destroy_rgw()
{
    if [ $# != 1 ]; then
        echo "Unknown host, please specify a valid host!"
        exit 1
    fi

    host=$1
    ceph auth del client.radosgw.gateway$host
    error_check ${FUNCNAME}

    ceph auth list | grep client.radosgw.gateway$host
    if [ $? -eq 0 ]; then
        echo "Error: ceph auth del client.radosgw.gateway$host"
        exit 1
    fi





    delstr="\[client\.radosgw\.gateway$host\]"
    eval sed -i 's/$delstr//g' $cluster_root/ceph.conf





    rm -f /etc/ceph/ceph.client.radosgw$host.keyring
    ssh $cluster_user@$host "rm -f /etc/ceph/ceph.client.radosgw$host.keyring"
    error_check ${FUNCNAME}
    push_conf
}

delete_rgw_pool()
{
    ceph osd pool delete .rgw.root .rgw.root --yes-i-really-really-mean-it
    ceph osd pool delete .rgw.control .rgw.control --yes-i-really-really-mean-it
    ceph osd pool delete .rgw .rgw --yes-i-really-really-mean-it
    ceph osd pool delete .rgw.gc .rgw.gc --yes-i-really-really-mean-it
    ceph osd pool delete .users .users --yes-i-really-really-mean-it
    ceph osd pool delete .users.uid .users.uid --yes-i-really-really-mean-it
    ceph osd pool delete .users.email .users.email --yes-i-really-really-mean-it
    ceph osd pool delete .rgw.buckets.index .rgw.buckets.index --yes-i-really-really-mean-it
    ceph osd pool delete .log .log --yes-i-really-really-mean-it
    ceph osd pool delete .rgw.buckets .rgw.buckets --yes-i-really-really-mean-it
    ceph osd pool delete .rgw.buckets.extra .rgw.buckets.extra --yes-i-really-really-mean-it
}

create_rgw_pool()
{
    isexist=`rados lspools | grep ".rgw" | wc -l`
    if [ $isexist -ne 0 ]; then
        echo "NOTICE: rgw pools may already exist:"
        rados lspools
        echo "WARNNING: delete them and create new rgw pools? yes/no"
        read answer
        case $answer in
            yes|YES) delete_rgw_pool;;
            *)       exit 1;;
        esac
    fi

    #ceph osd erasure-code-profile set dss_default directory=/usr/lib64/ceph/erasure-code plugin=jerasure k=4 m=1 --force
    ceph osd pool create .rgw.root 16 16
    ceph osd pool create .rgw.control 16 16
    ceph osd pool create .rgw 16 16
    ceph osd pool create .rgw.gc 16 16
    ceph osd pool create .users 16 16
    ceph osd pool create .users.uid 16 16
    ceph osd pool create .users.email 16 16
    ceph osd pool create .rgw.buckets.index 16 16
    ceph osd pool create .log 16 16
    #ceph osd pool create .rgw.buckets 128  erasure dss_default
    ceph osd pool create .rgw.buckets 128 128
    ceph osd pool create .rgw.buckets.extra 16 16
}

create_normal_pool()
{
    isexist=`rados lspools | grep $1 | wc -l`
    if [ $isexist -ne 0 ]; then
        echo "NOTICE: $1 pool may already exist:"
        rados lspools
        echo "WARNNING: delete it and create a new one? yes/no"
        read answer
        case $answer in
            yes|YES) ceph osd pool delete $1 $1 --yes-i-really-really-mean-it;;
            *)       exit 1;;
        esac
    fi

    ceph osd pool create $1 128 128
}

delete_all_pool()
{
    echo "WARRNING: this's a unrecoverabel operation, are you sure? yes/no"
    read answer
    case $answer in
        yes|YES) ;;
        *)       exit 1;;
    esac

    pool_list=`rados lspools | sed 's/\n/ /g'`
    for pool in $pool_list
    do
        ceph osd pool delete $pool $pool --yes-i-really-really-mean-it
    done
}

delete_rgw_pool_only()
{
    echo "WARRNING: this's a unrecoverabel operation, are you sure? yes/no"
    read answer
    case $answer in
        yes|YES) delete_rgw_pool;;
        *)       exit 1;;
    esac
}

delete_specific_pool()
{
    if [ $# != 1 ]; then
        echo "Unknown pool name ,check it pls!"
        exit 1
    fi

    echo "WARRNING: this's a unrecoverabel operation, are you sure? yes/no"
    read answer
    case $answer in
        yes|YES) ceph osd pool delete $1 $1 --yes-i-really-really-mean-it;;
        *)       exit 1;;
    esac
}

zap_alldisks()
{
    echo "Prepare to zap all disks in the cluster ..."
    cd $cluster_root

    for host in $osd_server
    do
        for disk in `cat $script_root/$host.disk`
        do
            zap_specific_disk $host:$disk

            #echo "Show information of $disk in $host:"
            #ssh $cluster_user@$host "fdisk -l $disk"
            #echo "WARNNING: This's a unrecoverabel operation, are you sure to zap $host:$disk? yes/no"
            #read answer
            #case $answer in
            #yes|YES) ;;
            #*)       continue;;
            #esac

            #ssh $cluster_user@$host "mount -l | awk '{print $1}' | grep $disk$data_idx"
            #if [ "$?" == "0" ]; then
            #    echo "mount: $disk$data_idx"
            #    ssh $cluster_user@$host "umount $disk$data_idx"
            #    error_check ${FUNCNAME}
            #fi

            #ceph-deploy disk zap $host:$disk
            #error_check ${FUNCNAME}
        done
    done

    echo "Zap all the disks over."
}

initntp_server()
{
    isrunning=`ps -elf | grep "$1 initntp" | grep -v grep | wc -l`
    if [ $isrunning -gt 2 ]; then
        echo "ntp is already inited"
        exit 1
    fi

    ntp_server_conf=/etc/ntp.conf
    ntp_log=`cat $ntp_server_conf | grep logfile | awk '{print $2}'`

    cat $ntp_server_conf | grep "^server" | grep -v "\<#" | while read line ; do
        ntpd_server=`echo $line | awk '{print $2}'`
        /usr/local/bin/ntpdate.binary -u $ntpd_server 1>/dev/null 2>&1
        /sbin/hwclock -w -u
    done 1>/dev/null 2>&1 &

    while true; do
        ntprunning=`service ntpd status | grep running | wc -l`
        if [ $ntprunning -eq 0 ]; then
            service ntpd start
        fi

        date_time=`date | awk '{print $4}'`
        hour=`echo $date_time | awk -F':' '{print $1}'`
        minute=`echo $date_time | awk -F':' '{print $2}'`
        second=`echo $date_time | awk -F':' '{print $3}'`

        if [ $hour -eq 23 ] && [ $minute -eq 59 ] && [ $second -eq 55 ]; then
            date=`date +%F`
            log_file=/log/ntp_$date.log
            if [ -e $ntp_log ]; then
                mv -f $ntp_log $log_file
            fi
            sleep 1
        fi

        sleep 5

    done &
}

initntp_client()
{
    echo "nothing to do"
}

init_ntp()
{
    initntp_server
    initntp_client
}

show_pgresult()
{
    ceph osd utilization
    end_time=`date +%s.%N`
    cost_time=`echo "$end_time - $start_time" | bc`
    echo ""
    echo Total reweight times: [$reweight_count]
    echo Total cost time: [$cost_time s]
    rm -f $pg_msg_file
}

rebalance_pg()
{
    target_threshold=$1
    reweight_count=0
    pg_msg_file=$script_root/pg.msg

    start_time=`date +%s.%N`
    while true
    do
        ceph osd utilization 1>$pg_msg_file
        min_osd=`cat $pg_msg_file | grep min |awk -F ' ' '{print $2}'`
        min_pg_num=`cat $pg_msg_file | grep min |awk -F ' ' '{print $4}'`
        min_ratio=`cat $pg_msg_file | grep min |awk -F ' ' '{print $6}'|sed 's/(//g'`
        max_osd=`cat $pg_msg_file | grep max |awk -F ' ' '{print $2}'`
        max_pg_num=`cat $pg_msg_file | grep max |awk -F ' ' '{print $4}'`
        max_ratio=`cat $pg_msg_file | grep max |awk -F ' ' '{print $6}'|sed 's/(//g'`
        avg_pg_num=`cat $pg_msg_file | head -1 | awk '{print $2}'`

        diff=`echo "scale=3; $min_pg_num - $avg_pg_num" | bc`
        min_diff=`echo ${diff#-}`
        diff=`echo "scale=3; $max_pg_num - $avg_pg_num" | bc`
        max_diff=`echo ${diff#-}`

        ret=`echo "$min_diff > $max_diff" | bc`
        if [ $ret -eq 1 ]; then
            target_osd=$min_osd
            osd_ratio=$min_ratio
            max_pg_diff=$min_diff
        else
            target_osd=$max_osd
            osd_ratio=$max_ratio
            max_pg_diff=$max_diff
        fi

        cur_threshold=`echo "scale=3; $max_pg_diff / $avg_pg_num" | bc`
        ret=`echo "$cur_threshold <= $target_threshold" | bc`
        if [ $ret -eq 1 ]; then
            show_pgresult
            exit 0
        else
            osd_weight=`ceph osd tree|grep "\<$target_osd\>"|awk '{print $2}'`
            weight_val=`echo "scale=6; $osd_weight / $osd_ratio" | bc`
            ceph osd crush reweight $target_osd $weight_val
            error_check ${FUNCNAME}
            reweight_count=`expr $reweight_count + 1`
        fi
    done
}

fio_perf()
{
    if [ $# != 4 ]; then
        echo "Error param, fio {randwrite|etc.} {nrfiles} {block-size} {path}"
        exit 1
    fi

    blkval=`echo $3 | sed 's/[a-z | A-Z]//g'`
    blkunit=`echo $3 | sed 's/[0-9]//g'`
    objsize=`expr $2 \* $blkval`
    filename=$1-$3-$objsize$blkunit.txt
    result_file=$1-$3-$objsize$blkunit.result
    total_aggrbval=0
    total_runtval=0

    #objval=`echo $3 | sed 's/[a-z | A-Z]//g'`
    #objunit=`echo $3 | sed 's/[0-9]//g'`

    #case $blkunit in
    #    k|K)   ;;
    #    m|M)   blkval=`expr $blkval \* 1024`;;
    #    g|G)   blkval=`expr $blkval \* 1048576`;;
    #    *)     echo "WARNNING: invalid block-size: $2"
    #           exit 1;;
    #esac

    #case $objunit in
    #    k|K)   ;;
    #    m|M)   objval=`expr $objval \* 1024`;;
    #    g|G)   objval=`expr $objval \* 1048576`;;
    #    *)     echo "WARNNING: invalid object-size: $3"
    #           exit 1;;
    #esac

    if [ ! -d $4 ]; then
        mkdir -p $4
    fi

    cd $4
    for ((i=0;i<3;i++))
    do
        echo "fio -nrfiles=$2 -rw=$1 -bs=$3 -size=$objsize$blkunit -name=$filename"
        echo "fio -nrfiles=$2 -rw=$1 -bs=$3 -size=$objsize$blkunit -name=$filename" >> $result_file
        fio -nrfiles=$2 -rw=$1 -bs=$3 -size=$objsize$blkunit -name=$filename > tmp.result
        write_info=`cat ./tmp.result | grep write:`
        WRITE_info=`cat ./tmp.result | grep WRITE:`
        echo $write_info
        echo $WRITE_info
        runt=`echo $write_info | awk -F ',' '{print $4}' | awk -F '=' '{print $2}'`
        aggrb=`echo $WRITE_info | awk -F ',' '{print $2}' | awk -F '=' '{print $2}'`
        runtval=`echo $runt | grep -Eo [0-9]+`
        runtunit=`echo $runt | sed 's/[0-9]//g'`
        aggrbval=`echo $aggrb | grep -Eo [0-9]+`
        aggrbunit=`echo $aggrb | awk -F '/' '{print $1}' | sed 's/[0-9]//g'`
        echo $runtval   $runtunit >> $result_file
        echo $aggrbval   $aggrbunit/s >> $result_file
        case $aggrbunit in
            KB)   ;;
            MB)   aggrbval=`expr $aggrbval \* 1024`;;
            GB)   aggrbval=`expr $aggrbval \* 1048576`;;
            *)    echo "WARNNING: invalid object-size: $3"
                  exit 1;;
        esac
        total_aggrbval=`expr $total_aggrbval + $aggrbval`
        total_runtval=`expr $total_runtval + $runtval`
        rm -f $filename*
    done

    rm -f tmp.result
    average_rggrbval=`expr $total_aggrbval / 3`
    average_runtval=`expr $total_runtval / 3`
    echo "=====Average test result=====" >> $result_file
    echo "runtine: $average_runtval $runtunit" >> $result_file
    echo "aggrb:   $average_rggrbval $aggrbunit/s" >> $result_file
}

cluster_schedule()
{
    echo "nothing to do"
}

init_cluster_env()
{
    data_idx=1
    journal_idx=2

    mon_list=`cat $cluster_conf | grep mon_list | awk -F'=' '{print $2}'`
    osd_list=`cat $cluster_conf | grep osd_list | awk -F'=' '{print $2}'`
    rgw_list=`cat $cluster_conf | grep rgw_list | awk -F'=' '{print $2}'`

    mon_server=`echo $mon_list | sed 's/ //g' | sed 's/,/\n/g' | sort -u | tr -s '\n' ' '`
    osd_server=`echo $osd_list | sed 's/ //g' | sed 's/,/\n/g' | sort -u | tr -s '\n' ' '`
    rgw_server=`echo $rgw_list | sed 's/ //g' | sed 's/,/\n/g' | sort -u | tr -s '\n' ' '`
    ceph_servers=`echo "$mon_list,$osd_list,$rgw_list" | sed 's/ //g' | sed 's/,/\n/g' | sort -u | tr -s '\n' ' '`
    admin_server=`cat $cluster_conf | grep admin_node | awk -F'=' '{print $2}' | sed 's/ //g'`

    inkscope_admin=`cat $cluster_conf | grep inkscope_admin | awk -F '=' '{print $2}' | sed 's/ //g'`
    calamari_admin=`cat $cluster_conf | grep calamari_admin | awk -F '=' '{print $2}' | sed 's/ //g'`


    if [ -d $cluster_root ]; then
        break
    else
        mkdir -p $cluster_root
        error_check ${FUNCNAME}
    fi
}

get_host_device()
{
    #for host in $osd_server
    #do  
    #    cat $cluster_conf | while read key value;
    #    do
    #        if [ "$key" != "$host" ]; then
    #            continue
    #        fi

    #        touch $script_root/$host.disk
    #        echo $value | awk -F'=' '{print $2}' | sed 's/ //g' | sed 's/,/ /g' > $script_root/$host.disk
    #    done
    #done

    for host in $osd_server
    do   
        os_dev=`ssh $host mount -l | grep "/dev/sd" | grep "boot" |head -1| awk '{print $1}' | sed 's/[0-9]//g' | awk -F '/' '{print $3}'`
        lvm_dev=`ssh $host blkid | grep "/dev/sd" | grep "LVM" | grep -v "$os_dev" | head -1 | awk -F':' '{print $1}' | sed 's/[0-9]//g' | awk -F '/' '{print $3}'`

        if [ "$lvm_dev" != "" ]; then
            #idle_dev=`ssh $host lsblk | grep "^sd" | grep -v "$os_dev" | grep -v "$lvm_dev" |  awk -F ' ' '{print $1}' | sed 's/\n/ /g'`
            idle_dev=`ssh $host lsblk | grep "^sd" | awk -F ' ' '{print $1}' | grep -v "^$os_dev$" | grep -v "^$lvm_dev$" | sed 's/sd/\/dev\/sd/g' | sed 's/\n/ /g'`
        else
            idle_dev=`ssh $host lsblk | grep "^sd" | awk -F ' ' '{print $1}' | grep -v "^$os_dev$" | sed 's/sd/\/dev\/sd/g' | sed 's/\n/ /g'`
        fi   

        echo $idle_dev > $script_root/$host.disk
    done
}

init_autossh()
{
    if [ -e /root/.ssh/known_hosts ]; then
        >/root/.ssh/known_hosts
    fi

    ssh-keygen
    for host in $ceph_servers
    do
        echo "Prepare to auto ssh $host ..."
        ssh-copy-id $cluster_user@$host
        error_check ${FUNCNAME}
    done

    echo "Initialize autossh over."
}

init_mons()
{
    echo "Prepare to initialize mons, pls wait ..."
    cd $cluster_root
    ceph-deploy new $mon_server
    error_check ${FUNCNAME}
    ceph-deploy --overwrite-conf mon create-initial
    error_check ${FUNCNAME}

    #ceph-deploy new $admin_server
    #for host in `echo "$admin_server,$mon_server" | sed 's/ //g' | sed 's/,/\n/g' | sort | uniq -u | tr -s '\n' ' '`
    #do
    #    echo ""
    #    ceph-deploy create mon $host
    #done
    echo "Initialize mons over."
}

init_osds()
{
    echo "Prepare to initialize osds, pls wait ..."
    cd $cluster_root
    get_host_device
    #zap_alldisks

    for host in $osd_server
    do
        for disk in `cat $script_root/$host.disk`
        do
            ceph-deploy --overwrite-conf osd prepare $host:$disk
            error_check ${FUNCNAME}
            ceph-deploy --overwrite-conf osd activate $host:$disk$data_idx:$disk$journal_idx
            error_check ${FUNCNAME}
        done
        rm -f $script_root/$host.disk
    done

    echo "Initialize osds over."
}

init_rgws()
{
    echo "Prepare to initialize rgws, pls wait ..."

    for host in $rgw_server
    do
        create_rgw $host
    done

    echo "Initialize rgws over."
}

init_restapi()
{
    echo "Prepare to initialize ceph-rest-api, pls wait ..."

    ceph auth get-or-create client.restapi mds 'allow' osd 'allow *' mon 'allow *' > /etc/ceph/ceph.client.restapi.keyring
cat >> $cluster_root/ceph.conf << EOF

[client.restapi]
log_file = /dev/null
keyring = /etc/ceph/ceph.client.restapi.keyring
EOF

    ceph auth list | grep client.restapi
    error_check ${FUNCNAME}

    #TODO: copy the ceph-rest-api keyring, ceph.conf, ceph-admin keyring to inkscope host
    echo "Initialize ceph-rest-api over."
}

push_conf()
{
    echo "Prepare to push ceph.conf , pls wait ..."
    cd $cluster_root

    for host in $ceph_servers
    do
        ceph-deploy --overwrite-conf config push $host
        ceph-deploy --overwrite-conf admin $host
        error_check ${FUNCNAME}
    done

    echo "Push ceph.conf over."
}

show_cluster_status()
{
    ceph -s
}

deploy_cluster()
{
    #init_autossh
    init_mons
    init_osds
#sleep 3
    #init_rgws
#sleep 3
    #init_restapi
sleep 3
    push_conf
sleep 3
    show_cluster_status
    #TODO: start up osd service when booting
}

deploy_calamari()
{
    echo "Prepare to deploy calamari ..."

    calamari_pkg=$script_root/centos6calamari.tar.gz
    admin_root=$script_root/centos6calamari/calamariserver/
    slave_root=$script_root/centos6calamari/clusternode/

    if [ ! -e $calamari_pkg ]; then
        echo "There is no calamari package in current directory, check it pls!"
        exit 1
    fi

    cd $script_root
    tar zxf $calamari_pkg
    scp -r $admin_root $cluster_user@$calamari_admin:/opt
    error_check ${FUNCNAME}
    ssh $calamari_admin "cd /opt/calamariserver/; sh install.sh"
    error_check ${FUNCNAME}

    for host in $ceph_servers
    do
        scp -r $slave_root $cluster_user@$host:/opt
        error_check ${FUNCNAME}
        ssh $host "cd /opt/clusternode/; sh install.sh"
        error_check ${FUNCNAME}
    done

    echo "Finish deploying calamari, run it if necessary!"
    echo "Finish deploying calamari, you can visit the web address: http://{$calamari_admin ip}:80"
}

start_calamari()
{
    ssh $calamari_admin "cd /opt/calamariserver/; sh start.sh"
    error_check ${FUNCNAME}

    for host in $ceph_servers
    do
        ssh $host "cd /opt/clusternode/; sh start.sh $calamari_admin"
        error_check ${FUNCNAME}
    done

    echo "Calamari already started, visit the web via: http://{$calamari_admin ip}:80"
}

stop_calamari()
{
    ssh $calamari_admin "cd /opt/calamariserver/; sh stop.sh"
    error_check ${FUNCNAME}
    service httpd stop
    error_check ${FUNCNAME}

    for host in $calamari_admin
    do
        ssh $host "cd /opt/clusternode/; sh stop.sh"
        error_check ${FUNCNAME}
    done

    echo "Finish stopping calamari service ."
}

destroy_cluster()
{
    echo "WARNNING: all data will be destroyed in dirs which include /etc/ceph/,/var/lib/ceph/ and /opt/cluster/, confirm it ! (yes/no)"
    read answer
    case $answer in
        yes|YES)   ;;
        *)         exit 1;;
    esac

    get_host_device
    rm -rf $cluster_root
    echo "nodes:[$ceph_servers]"
    for host in $ceph_servers
    do
        ssh $host "service ceph -a stop"
        sleep 1
        #cmd="for i in `ls /var/lib/ceph/osd/`;do fuser -mk /var/lib/ceph/osd/$i;usleep 500000;done"
        #ssh $host $cmd
        #sleep 1
        ssh $host "umount /var/lib/ceph/osd/*"
        sleep 1
    done

    for host in $ceph_servers
    do
        ssh $host "rm -rf /var/lib/ceph/bootstrap-mds/*"
        ssh $host "rm -rf /var/lib/ceph/bootstrap-osd/*"
        ssh $host "rm -rf /var/lib/ceph/bootstrap-rgw/*"
        ssh $host "rm -rf /var/lib/ceph/mds/*"
        ssh $host "rm -rf /var/lib/ceph/mon/*"
        ssh $host "rm -rf /var/lib/ceph/osd/*"
        ssh $host "rm -rf /var/lib/ceph/radosgw/*"
        ssh $host "rm -rf /var/lib/ceph/tmp/*"
        ssh $host "rm -rf /etc/ceph/*"
        ssh $host "rm -rf /var/run/ceph/*"
        ssh $host "rm -rf /var/log/ceph/*"
        sleep 1
    done

    for host in $ceph_servers
    do
        for disk in `cat $script_root/$host.disk`
        do 
           #ssh $host mkfs.xfs -d agcount=1 -f -i size=2048 $disk
           ssh $host mkfs.xfs -f $disk
        done
    done
}

zap_disks_only()
{
    if [ $# != 1 ]; then
        echo "Unknown param, check it pls!"
        exit 1
    fi

    get_host_device
    cd $cluster_root

    case $1 in
        all)  zap_alldisks;;
        *)    zap_specific_disk $1;;
    esac
}

autossh_only()
{
    init_autossh
}

pushconf_only()
{
    push_conf
}

push_hosts()
{
    hosts_file=/etc/hosts
    if [ ! -s $hosts_file ]; then
        echo "$hosts_file doesn't exist or without configuration, check it pls!"
        exit 1
    fi

    echo "Show the configuration in /etc/hosts:"
    cat /etc/hosts
    echo "WARNNING: precheck the configuration, and comfirm it. yes/no?"
    read answer
    case $answer in
        yes|YES) ;;
        *)       exit 1;;
    esac

    for host in $ceph_servers
    do
        scp $hosts_file $cluster_user@$host:$hosts_file
    done
}

start_service()
{
    if [ $# != 1 ]; then
        echo "Unknown param, check it pls!"
        exit 1
    fi

    case $1 in
        inkscope)   start_inkscope;;
        calamari)   start_calamari;;
        *)
            echo "Unknown param, check it pls!"
            exit 1;;
    esac
}

stop_service()
{
    if [ $# != 1 ]; then
        echo "Unknown param, check it pls!"
        exit 1
    fi

    case $1 in
        cluster)   stop_cluster;;
        inkscope)  stop_inkscope;;
        calamari)  stop_calamari;;
        *)         
            echo "Unknown param, check it pls!"
            exit 1;;
    esac
}

uninstall_program()
{
    if [ $# != 1 ]; then
        echo "Unknown param, check it pls!"
        exit 1
    fi

    case $1 in
        cluster)    destroy_cluster;;
        inkscope)   destroy_inkscope;;
        calamari)   destroy_calamari;;
        *)
            echo "Uknown param, check it pls!"
            exit 1;;
    esac
}

preinstall_check()
{
    ceph-deploy --version
    if [ "$?" -ne "0" ]; then
        echo "==========WARNNING: ceph-deploy not be installed=========="
        exit 1
    fi

    ver=""
    for host in $ceph_servers
    do
        timeout 10s ssh $host echo "==========$host is OK========="
        if [ "$?" != "0" ]; then
            echo "Connection to $host timed out, check it pls!"
            exit 1
        fi

        platform=$(uname -i)
        version=$(lsb_release -r | awk '{print $2}')
        if [[ $platform != "x86_64" || $version != "6.7" ]]; then
            echo "Only for 64bit CentOS 6.7 release!"
            exit 1
        fi

        if [ "$ver" = "" ]; then
            ver=`ssh $host ceph -v | awk '{print $4}' | sed 's/(//g' | sed 's/)//g'`
        else
            if [ "$ver" != "`ssh $host ceph -v | awk '{print $4}' | sed 's/(//g' | sed 's/)//g'`" ]; then
                echo "===========WARNNING: ceph version is diffrent=========="
                exit 1
            fi
        fi
    done

    get_host_device
    for host in $osd_server
    do
        os_dev=`ssh $host mount -l | grep "boot" |head -1| awk '{print $1}' | sed 's/[0-9]//g'`
        lvm_dev=`ssh $host blkid | grep "LVM" | grep -v "$os_dev" | head -1 | awk -F':' '{print $1}' | sed 's/[0-9]//g'`
        idle_dev=`ssh $host blkid | grep -v "$os_dev" | awk -F':' '{print $1}' | sed 's/[0-9]//g' | sed 's/\n/ /g'`

        #echo "os:[$os_dev] lvm:[$lvm_dev] idle:[$idle_dev]"
        for disk in `cat $script_root/$host.disk`
        do
            #echo "disk:[$disk]"
            if [ "$disk" = "$os_dev" ]; then
                echo "==========ERROR: $host:$disk is OS device========="
                exit 1
            fi

            if [ "$disk" = "$lvm_dev" ]; then
                echo "==========WARNNING: $disk may be a OS LVM device=========="
                fdisl -l $disk
                echo "WARNNING: are you sure to use it as a OSD? yes/no"
                read answer
                case $answer in
                    yes|YES)  ;;
                    *)        
                        echo "Check the cluster deploy configuration file pls."
                        exit 1;;
                esac
            fi

            isexist=0
            for idle_disk in $idle_dev
            do
                if [ $disk != $idle_disk ];then
                    continue
                else
                    isexist=1
                    break;
                fi
            done
            if [ $isexist != 1 ]; then
                echo "WARNNING: $disk is not found in $host, check it pls!"
                exit 1
            fi
        done
    done
}

autostart_osd()
{
    osd_list=`ceph-disk list |grep "osd" |awk '{print $1}' | sed 's/1//g'| sed 's/\/dev\///g'`
    for osd in $osd_list
    do
        ceph-disk-udev $data_idx $osd$data_idx $osd
        ceph-disk-udev $journal_idx $osd$journal_idx $osd
    done
}

osd_daemon()
{
    isrunning=`ps -elf | grep "$1 daemon" | grep -v grep | wc -l`
    if [ $isrunning -gt 2 ]; then
        echo "is already running"
        exit 1
    fi

    while true
    do
        for i in `find -L /var/lib/ceph/osd -mindepth 1 -maxdepth 1 -type d -printf '%f\n'`
        do  
            id=`echo $i | sed 's/[^-]*-//'`
            if [ -e /var/run/ceph/osd.$id.pid ]; then
                pid=`cat /var/run/ceph/osd.$id.pid`
                if [ -z $pid ]; then
                    service ceph start osd.$id 1>/dev/null 2>/dev/null
                else
                    [ ! -e /proc/$pid ] && service ceph start osd.$id 1>/dev/null 2>/dev/null
                fi  
            else
                service ceph start osd.$id 1>/dev/null 2>/dev/null
            fi  
        done
        sleep 5
    done &
}

create_pool()
{
    if [ $# != 1 ]; then
        #TODO: can not specify pg num, pgp num, etc.
        echo "Unknown param, check it pls!"
        exit 1
    fi

    case $1 in
        rgw)  create_rgw_pool;;
        *)    create_normal_pool $1;;
    esac
}

del_pool()
{
    if [ $# != 1 ]; then
        echo "Unknown param, check it pls!"
        exit 1
    fi

    case $1 in
        all)  delete_all_pool;;
        rgw)  delete_rgw_pool_only;;
        *)    delete_specific_pool $1;;
    esac
}

add_monitor()
{
    if [ $# != 1 ]; then
        echo "Unknown param, check it pls!"
        exit 1
    fi

    cd $cluster_root
    ceph-deploy mon create $1
    error_check ${FUNCNAME}
    push_conf
}

init_os()
{
    if [ $# != 1 ]; then
        echo "Unknown param, check it pls!"
        exit 1
    fi

    for host in $ceph_servers
    do
        ssh $host "if [ ! -d $script_root ];then mkdir -p $script_root;fi"
        error_check ${FUNCNAME}
        scp -r $script_root/ceph-auto-deploy.sh $cluster_user@$host:$script_root/

        ssh $host "sed -i '/ceph-auto-deploy/d' /etc/rc.d/rc.local"
        error_check ${FUNCNAME}

        ssh $host "echo 'cd $script_root;$0 autostart' >> /etc/rc.d/rc.local"
        error_check ${FUNCNAME}
        ssh $host "echo 'cd $script_root;$0 initdisk' >> /etc/rc.d/rc.local"
        error_check ${FUNCNAME}
        #ssh $host "echo 'cd $script_root;$0 daemon' >> /etc/rc.d/rc.local"
        #error_check ${FUNCNAME}
    done

    echo 1 > /sys/module/printk/parameters/time
    #TODO: ntp server
}

init_disk_param()
{
    os_dev=`mount -l | grep "/dev/sd" | grep "boot" |head -1| awk '{print $1}' | sed 's/[0-9]//g' | awk -F '/' '{print $3}'`
    lvm_dev=`blkid | grep "/dev/sd" | grep "LVM" | grep -v "$os_dev" | head -1 | awk -F':' '{print $1}' | sed 's/[0-9]//g' | awk -F '/' '{print $3}'`
    if [ "$lvm_dev" != "" ]; then
        idle_dev=`lsblk | grep "^sd" | awk -F ' ' '{print $1}' | grep -v "^$os_dev$" | grep -v "^$lvm_dev$" | sed 's/\n/ /g'`
    else
        idle_dev=`lsblk | grep "^sd" | awk -F ' ' '{print $1}' | grep -v "^$os_dev$" | sed 's/\n/ /g'`
    fi

    for disk in $idle_dev
    do
        echo 4096 > /sys/block/$disk/queue/read_ahead_kb
        #if [  ]; then
        #    echo noop > /sys/block/$disk/queue/scheduler
        #else
            echo deadline > /sys/block/$disk/queue/scheduler
        #fi
    done
}

mount_osd()
{
    if [ $# != 1 ]; then
        echo "Unknown host, check it pls!"
        exit 1
    fi

    host=$1
    fstab=/etc/fstab
    fstab_bak=/etc/fstab.bak
    echo > $script_root/osd_tmp
    echo > $script_root/fstab_tmp
    ssh $host cp $fstab $fstab_bak
    ssh $host blkid | while read line
    do
        devname=`echo $line | awk '{print $1}' | sed 's/://' | awk -F/ '{print $3}'`
        error_check ${FUNCNAME}
        echo "$devname `echo $line | awk '{print $2}'`" >> osd_tmp
    done

    ssh $host mount -l | grep osd | while read line
    do
        devname=`echo $line | awk '{print $1}' | awk -F/ '{print $3}'`
        fstype=`echo $line | awk '{print $5}'`
        echo -e `grep $devname osd_tmp | awk '{print $2}'`"\t"`echo $line | awk '{print $3}'`"\t"$fstype"\tdefaults\t0\t0" >> fstab_tmp
    done
    rm -f osd_tmp
    sed -i 's/"//g' fstab_tmp
    ssh $host "sed -i '/\/var\/lib\/ceph\/osd\/ceph/d' /etc/fstab"
    ssh $host "echo '`cat fstab_tmp`' >> $fstab"
}

del_monitor()
{
    if [ $# != 1 ]; then
        echo "Unknown param, check it pls!"
        exit 1
    fi

    cd $cluster_root
    echo "===============start to remove mon.$1 from the cluster==============="

    case $1 in
        all)
            for host in $mon_servers
            do
                ceph-deploy mon destroy $host
                error_check ${FUNCNAME}
            done
            for host in $mon_servers
            do
                ssh $host service ceph stop mon.$host
                error_check ${FUNCNAME}
                ssh $host ceph mon remove $host
                error_check ${FUNCNAME}
            done
    esac
    ceph-deploy mon destory $1
    error_check ${FUNCNAME}
    push_conf
}

add_osd()
{
    if [ $# != 1 ]; then
        echo "Unknown param, check it pls!"
        exit 1
    fi

    host=`echo $1 | awk -F ':' '{print $1}'`
    devname=`echo $1 | awk -F ':' '{print $2}'`

    cd $cluster_root
    zap_specific_disk $host:$devname
    ceph-deploy --overwrite-conf osd prepare $host:$devname
    ceph-deploy --overwrite-conf osd activate $host:$devname$data_idx:$devname$journal_idx
}

del_osd()
{
    if [ $# != 1 ]; then
        echo "Unknown param, check it pls!"
        exit 1
    fi

    host=`echo $1 | awk -F ':' '{print $1}'`
    osdname=`echo $1 | awk -F ':' '{print $2}'`
    osd_num=`echo $osdname | awk -F '.' '{print $2}'`

    ceph osd out $osd_num
    ssh $host service ceph stop $osdname
    ceph osd crush remove $osdname
    ceph auth del $osdname
    ceph osd rm $osdname
    ssh $host umount /var/lib/ceph/osd/ceph-$osd_num
}

add_radosgw()
{
    if [ $# != 1 ]; then
        echo "Unknown host, please specify a valid host!"
        exit 1
    fi

    create_rgw $1
}

del_radosgw()
{
    exit 0





    if [ $# != 1 ]; then
        echo "Unknown host, please specify a valid host!"
        exit 1
    fi

    destroy_rgw $1
}

test_func()
{
    isrun=`ps -elf | grep "$1 test" | grep -v grep | wc -l`
    if [ $isrun -gt 2 ]; then
        echo "is already running"
        exit 1
    fi
    while true; do
        sleep 5
    done&
}

if [ $# -lt 1 ]; then
    echo "Description:"
    echo "    This is a multifunctional script for ceph."
    usage
    exit 1
fi

cluster_user="root"
#cluster_root="/opt/ceph-cluster"
cluster_root="/opt/cluster/"
cluster_conf="cluster-deploy.conf"
script_root=$PWD

init_cluster_env

case $1 in
    -h|--help|help) help_info $0;;
    initos)         init_os $0;;
    initntp)        init_ntp $0;;
    initdisk)       init_disk_param;;
    balancepg)      rebalance_pg $2;;
    fio)            fio_perf $2 $3 $4 $5;;
    scheduler)      cluster_schedule;;
    cluster)        deploy_cluster;;
    inkscope)       deploy_inkscope;;
    calamari)       deploy_calamari;;
    start)          start_service $2;;
    stop)           stop_service $2;;
    uninstall)      uninstall_program $2;;
    mountosd)       mount_osd $2;;
    precheck)       preinstall_check;;
    autostart)      autostart_osd;;
    daemon)         osd_daemon $0;;
    createpool)     create_pool $2;;
    delpool)        del_pool $2;;
    zap)            zap_disks_only $2;;
    autossh)        autossh_only;;
    pushconf)       pushconf_only;;
    pushhosts)      push_hosts;;
    addmon)         add_monitor $2;;
    delmon)         del_monitor $2;;
    addosd)         add_osd $2;;
    delosd)         del_osd $2;;
    addrgw)         add_radosgw $2;;
    delrgw)         del_radosgw $2;;
    listmon)        list_mon;;
    listosd)        list_osd;;
    listpool)       list_pool;;
    listpg)         list_pg;;
    query)          query_cluster_detail;;
    test)           test_func $0;;
    *)              usage $0;;
esac
exit 0
