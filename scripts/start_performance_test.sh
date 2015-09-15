#! /bin/bash

# This script is used to create large amount of routes and VMs( or containers) for
# testing performance.
#
# Usage: ./start_performance_test.sh -e <environment> -rc <router count> -q <quit on error>
#

PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin
PROGNAME=`basename $0`
PREFIX='Test'
RESULT='result.txt'
FIXIP='10.0.0.10'
START_INDEX=51

exec > performance.log 2>&1
print_usag() {
    echo "Usage: $PROGNAME -e <environment> -rc <router count> -q <quit on error>"
    echo "Usage: $PROGNAME --help"
}

check_ping(){
    local start_date=$1
    echo "start_date=$start_date"
    local net_node=$2
    echo "net_node=$net_node"
    local ns=$3
    echo "ns=$ns"
    local ip=$4
    echo "ip=$ip"
    index=0
    retry=20
    status='active'
    while true; do
        ssh -i /root/docker.key $net_node "ip netns exec $ns ping -q -c5 $ip"
        [ $? -eq 0 ] && break
        sleep 1 
        index=$[index+1]
        [ $index -gt $retry ] && status='time out' && break
    done
    ssh -i /root/docker.key $net_node "cat /dev/null > /root/.ssh/known_hosts"
    end_date=`date '+%Y-%m-%d %T'`
    start_time=`date +%s -d "$start_date"`
    end_time=`date +%s -d "$end_date"`
    delta_time=$(($end_time-$start_time))
    echo -e "ssh $ip start time: $start_date" >> $RESULT
    echo -e "ssh $ip end time:   $end_date" >> $RESULT
    echo -e "ssh $ip delta time: $delta_time" >> $RESULT
    echo -e "status: $status" >> $RESULT
}

# Grab the command line arguments

while test -n "$1"; do
    case "$1" in
    --help)
        print_usage
        exit 0
        ;;
    -e)
        env=$2
        shift
        ;;
    -rc)
        count=$2
        shift
        ;;
    -q)
        quit_on_error=$2
        shift
        ;;
    *)       
        echo "Unknow argument: $1"
        print_usage
        exit 1
        ;;
    esac
    shift
done

# Set default value
env=${env:-"/root/admin_openrc"}
count=${count:-20}
quit_on_error=${quit_on_error:-0}
echo "The environment file: $env"
echo "The router count: $count"
echo "Whether to quit or not when create with error: $quit_on_error"

count=$[count+START_INDEX]
# Check environment file
if [ ! -f $env ]; then
    echo "Error: $env file is missing"
    exit 1
fi

# Check the "cirros" image
source $env
if [[ -z `glance image-list |grep cirros |grep active` ]]; then
    echo "Error: you need to pull cirros image firstly!"
    exit 1
fi

# Create result file
if [ ! -f "$RESULT" ]; then
  touch $RESULT
fi

## Start to create resources

# 1. Create the public network
#neutron net-create "$PREFIX-ext" --tenant-id $OS_TENANT_NAME --provider:network_type vxlan --router:external
#neutron subnet-create --name "$PREFIX-ext-subnet" --tenant-id $OS_TENANT_NAME "$PREFIX-ext" "172.24.0.0/16"
#subnet_id=$(neutron net-list | grep "$PREFIX-ext" | awk '{print $6}')
#echo "Ext networt subnet id:$subnet_id"
subnet_id=$(neutron net-list | grep t2-ext | awk '{print $6}')
ext_net_id=$(neutron net-list |grep  t2-ext | awk '{print $2}')


# Start the loop to create resources
for i in $(seq $START_INDEX $count)
do
    echo -e "$i:\n" >> $RESULT
    # 2.1 Create project user
    source $env
    openstack project create "$PREFIX-project$i"
    openstack user create "$PREFIX-project$i-user" --project "$PREFIX-project$i" --password "password"

    # 2.3 Create private network for VM(or container)
    neutron net-create "$PREFIX-private$i" --tenant-id "$PREFIX-project$i" --provider:network_type vxlan --shared
    neutron subnet-create --name "$PREFIX-private-subnet$i" "$PREFIX-private$i" "10.0.0.0/24"
    net_id=$(neutron net-list | grep "$PREFIX-private$i" | awk '{print $2}')
    private_subnet_id=$(neutron net-list | grep "$PREFIX-private$i" | awk '{print $6}')

    # 2.4 Bind private network to router
    neutron router-create "$PREFIX-router$i" --tenant-id "$PREFIX-project$i"
    neutron router-gateway-set "$PREFIX-router$i" "t2-ext"
    neutron router-interface-add "$PREFIX-router$i" $private_subnet_id

    # 2.5 Boot instance
    export OS_PROJECT_NAME="$PREFIX-project$i"
    export OS_TENANT_NAME="$PREFIX-project$i"
    export OS_USERNAME="$PREFIX-project$i-user"
    export OS_PASSWORD="password"
    nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
    nova secgroup-add-rule default tcp 22 22 0.0.0.0/0

    server_start_date=`date '+%Y-%m-%d %T'`
    nova boot --image cirros --flavor 10 --nic net-id=$net_id,v4-fixed-ip=$FIXIP "$PREFIX-instance$i"

    # 2.6 Associate floating ip to instance
    ip_addr=$(nova floating-ip-create t2-ext | grep -v -e "------" | grep -v -e "IP" | awk '{print $4}')
    floatingip_create_date=`date '+%Y-%m-%d %T'`
    nova floating-ip-associate "$PREFIX-instance$i" $ip_addr
    #router_id=$(neutron router-list | grep "$PREFIX-router$i" | awk '{print $2}')
    #port_id=$(neutron router-port-list "$PREFIX-router$i" | grep "172.24" | awk '{print $2}')
    #net_node=$(neutron port-show $port_id | grep "binding:host_id" | awk '{print $4}')
    check_ping "$server_start_date" neutron1 "qdhcp-$net_id" "$FIXIP"
    check_ping "$floatingip_create_date" neutron1 "qdhcp-$ext_net_id" $ip_addr
done
