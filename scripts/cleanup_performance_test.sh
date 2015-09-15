#! /bin/bash

# This script is used to create large amount of routes and VMs( or containers) for
# testing performance.
#
# Usage: ./cleanup_performance_test.sh -e <environment>
#

PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin
PROGNAME=`basename $0`
PREFIX='Test'

print_usage() {
    echo "Usage: $PROGNAME -e <environment>"
    echo "Usage: $PROGNAME --help"
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
echo "The environment file: $env"

# Check environment file
if [ ! -f $env ]; then
    echo "Error: $env file is missing"
    exit 1
fi

# Start to cleanup resources
source $env

# Clean up all instances
instances=$(nova list --all-tenants | grep $PREFIX | awk '{print $2}')
for i in $instances; do
    nova delete $i
done

# Retrive all test projects 
projects=$(openstack project list | grep $PREFIX | awk '{print $4}')

for p in $projects; do
    openstack user delete "$p-user"
    openstack project delete $p 
done


# Clean up external network
source $env

# 4. Clean up all floating ip addresses
ip_addrs=$(nova floating-ip-list | grep $PREFIX | awk '{print $2}')
for i in $ip_addrs; do
    nova floating-ip-delete $i
done

# 3. Clean up all subnets
subnets=$(neutron subnet-list | grep $PREFIX | awk '{print $2}')
for i in $subnets; do
    ports=$(neutron port-list | grep $i | awk '{print $2}')
    for p in $ports; do
        neutron port-delete $p
    done
    #neutron subnet-delete $i
done

# 2. Clean up all routers
routers=$(neutron router-list | grep $PREFIX | awk '{print $2}')
ext_subnet_id=$(neutron net-list |grep "t2-ext" | awk '{print $6}')
for i in $routers; do
    subnets=$(neutron router-port-list $i | grep subnet_id | grep -v -e "$ext_subnet_id" | awk -F[',',':','"'] '{print $10}' | uniq)
    for s in $subnets; do
        neutron router-interface-delete $i $s
        neutron subnet-delete $s
    done
    neutron router-gateway-clear $i
    neutron router-delete $i
done

# 4. Clean up all private networks
networks=$(neutron net-list | grep $PREFIX | awk '{print $2}')
for i in $networks; do
    neutron net-delete $i
done

neutron subnet-delete "$PREFIX-ext-subnet"
neutron net-delete "$PREFIX-ext"

# Clean up HA tenant network
subnets=$(neutron subnet-list | grep -e "HA subnet tenant" | awk '{print $2}')
for s in $subnets; do
    neutron subnet-delete $s
done
networks=$(neutron net-list |grep -e "HA network tenant" | awk '{print $2}')
for n in $networks ; do
    neutron net-delete $n
done

echo "All resources have been cleaned successfully!"
