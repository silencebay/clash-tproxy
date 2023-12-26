#!/bin/bash

source /usr/lib/mihomo/log.sh

set_localnetwork() {
    log "[ipset] Setting localnetwork"
    if [ -z "${LOCALNETWORK}" ]; then
        LOCALNETWORK="127.0.0.0/8,10.0.0.0/8,192.168.0.0/16,224.0.0.0/4,172.16.0.0/12"
    fi
    IFS=',' read -ra LOCALNETWORK <<< "$LOCALNETWORK"
    ipset create localnetwork hash:net
    # append local machine ip
    hostnames=$(hostname -i)
    IFS=' ' read -ra hostnames <<< "$hostnames"
    for entry in "${hostnames[@]}"; do
        LOCALNETWORK+=("$entry")
    done

    for entry in "${LOCALNETWORK[@]}"; do
        log "[ipset] Adding '${entry}'"
        ipset add localnetwork ${entry}
    done
    log "[ipset] setting process done."
}

readonly PROXY_BYPASS_USER="abc"
# readonly PROXY_BYPASS_CGROUP="0x100000"
readonly PROXY_FWMARK="0x1"
readonly PROXY_ROUTE_TABLE="0x1"
readonly PROXY_DNS_PORT="1053"
readonly PROXY_TUN_DEVICE_NAME="utun"