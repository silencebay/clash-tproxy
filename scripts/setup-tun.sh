#!/bin/bash

log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

set_localnetwork() {
    log "[ipset] Setting localnetwork"
    if [ -z "${LOCALNETWORK}" ]; then
        LOCALNETWORK="127.0.0.0/8,10.0.0.0/8,192.168.0.0/16,224.0.0.0/4,172.16.0.0/12"
    fi
    IFS=',' read -ra LOCALNETWORK <<< "$LOCALNETWORK"
    ipset create localnetwork hash:net
    for entry in "${LOCALNETWORK[@]}"; do
        log "[ipset] Adding '${entry}'"
        ipset add localnetwork ${entry}
    done
    log "[ipset] setting process done."
}


readonly PROXY_BYPASS_USER="nobody"
# readonly PROXY_BYPASS_CGROUP="0x16200000"
readonly PROXY_FWMARK="0x162"
readonly PROXY_ROUTE_TABLE="0x162"
readonly PROXY_DNS_PORT="1053"
readonly PROXY_TUN_DEVICE_NAME="utun"

while true; do
    ip link show $PROXY_TUN_DEVICE_NAME
    [ $? -eq 0 ] && break
    sleep 1
done

if [ "${EN_MODE:-fake-ip}" = "fake-ip" ]; then
    ip tuntap add "$TUN_DEV" mode tun user $CLASH_USER
    ip link set "$TUN_DEV" up
    ip addr add "$TUN_NET" dev "$TUN_DEV"
else
    set_localnetwork

    #/opt/script/setup-clash-cgroup.sh

    ip route replace default dev "$PROXY_TUN_DEVICE_NAME" table "$PROXY_ROUTE_TABLE"

    ip rule add fwmark "$PROXY_FWMARK" lookup "$PROXY_ROUTE_TABLE"

    iptables -t mangle -N CLASH
    iptables -t mangle -F CLASH
    iptables -t mangle -A CLASH -m owner --uid-owner "$PROXY_BYPASS_USER" -j RETURN
    iptables -t mangle -A CLASH -p tcp --dport 53 -j MARK --set-mark "$PROXY_FWMARK"
    iptables -t mangle -A CLASH -p udp --dport 53 -j MARK --set-mark "$PROXY_FWMARK"

    #iptables -t mangle -A CLASH -m owner --uid-owner systemd-timesync -j RETURN
    #iptables -t mangle -A CLASH -m cgroup --cgroup "$PROXY_BYPASS_CGROUP" -j RETURN
    iptables -t mangle -A CLASH -m addrtype --dst-type BROADCAST -j RETURN
    iptables -t mangle -A CLASH -m set --match-set localnetwork dst -j RETURN
    iptables -t mangle -A CLASH -j MARK --set-mark "$PROXY_FWMARK"

    iptables -t nat -N CLASH_DNS
    iptables -t nat -F CLASH_DNS
    iptables -t nat -A CLASH_DNS -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A CLASH_DNS -m owner --uid-owner "$PROXY_BYPASS_USER" -j RETURN
    #iptables -t nat -A CLASH_DNS -m owner --uid-owner systemd-timesync -j RETURN
    #iptables -t nat -A CLASH_DNS -m cgroup --cgroup "$PROXY_BYPASS_CGROUP" -j RETURN
    iptables -t nat -A CLASH_DNS -p udp -j REDIRECT --to-ports "$PROXY_DNS_PORT"

    iptables -t mangle -I OUTPUT -j CLASH
    iptables -t mangle -I PREROUTING -m set ! --match-set localnetwork dst -j MARK --set-mark "$PROXY_FWMARK"

    iptables -t nat -I OUTPUT -p udp --dport 53 -j CLASH_DNS
    iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to "$PROXY_DNS_PORT"
fi

ip addr