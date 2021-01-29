#!/bin/bash

source /usr/lib/clash/common.sh

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

fireqos start