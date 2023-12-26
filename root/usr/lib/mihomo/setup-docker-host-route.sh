#!/bin/bash

source /usr/lib/mihomo/log.sh

if [ "${DOCKER_HOST_INTERNAL}x" != "x" ]; then
    # Get the list of network interfaces
    # interfaces=$(ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -v lo)
    # first_usable_ip=$(ipcalc -n $DOCKER_HOST_INTERNAL | cut -d'=' -f2 | awk '{sub(/\.[0-9]+$/, ".1"); print}')
    # # Loop through each interface and ping the IP address
    # for iface in $interfaces
    # do
    #     ping -c 1 -W 1 -I $iface $first_usable_ip > /dev/null 2>&1
    #     if [ $? -eq 0 ]; then
    #         ip r add $DOCKER_HOST_INTERNAL dev $iface
    #         break
    #     fi
    # done
    # Check if the $DOCKER_HOST_INTERNAL can be cut by comma and the second element exists
    if echo $string | grep -q ',' && [ -n "$(echo $string | cut -d',' -f2)" ]; then
        net=$(echo $DOCKER_HOST_INTERNAL | cut -d',' -f1)
        iface=$(echo $DOCKER_HOST_INTERNAL | cut -d',' -f2)
        ip r add $net dev $iface
    else
        min_hop=1000
        first_usable_ip=$(ipcalc -n $DOCKER_HOST_INTERNAL | cut -d'=' -f2 | awk '{sub(/\.[0-9]+$/, ".1"); print}')
        for iface in $(ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -v lo); do
            hops=$(traceroute -m 5 -n -w 1 $first_usable_ip -i $iface | tail -1 | awk '{print $1}')
            if [ "$hops" = "*" ]; then
                hops=1000
            fi
            if [ "$hops" -lt "$min_hop" ]; then
                min_hop=$hops
                min_iface=$iface
            fi
        done
        # Check if a minimum hop count was found
        if [ $min_hop -eq 1000 ]; then
            log "Unable to reach $DOCKER_HOST_INTERNAL from any network interface"
        else
            ip r add $DOCKER_HOST_INTERNAL dev $min_iface
        fi
    fi
fi
