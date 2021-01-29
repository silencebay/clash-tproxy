#!/bin/bash

source /usr/lib/clash/common.sh

# ROUTE RULES
ip rule add fwmark "$PROXY_FWMARK" table 100
ip route add local default dev lo table 100

# 本机流量
set_localnetwork

# LOCAL CLIENTS
iptables -t mangle -N CLASH
iptables -t mangle -A CLASH -m addrtype --dst-type BROADCAST -j RETURN
iptables -t mangle -A CLASH -m set --match-set localnetwork dst -j RETURN
# prevent dns redirect
iptables -t mangle -A CLASH -p udp --dport 53 -j RETURN
# prevent zerotier redirect
iptables -t mangle -A CLASH -p udp --dport 9993 -j RETURN
iptables -t mangle -A CLASH -p udp -j TPROXY --on-port 7893 --tproxy-mark "$PROXY_FWMARK"
iptables -t mangle -A CLASH -p tcp -j TPROXY --on-port 7893 --tproxy-mark "$PROXY_FWMARK"
# REDIRECT
iptables -t mangle -A PREROUTING -j CLASH

# LOCAL MACHINE
iptables -t mangle -N CLASH_MASK
iptables -t mangle -A CLASH_MASK -m addrtype --dst-type BROADCAST -j RETURN
iptables -t mangle -A CLASH_MASK -m set --match-set localnetwork dst -j RETURN
iptables -t mangle -A CLASH_MASK -d 255.255.255.255/32 -j RETURN
iptables -t mangle -A CLASH_MASK -p udp --dport 53 -j RETURN
iptables -t mangle -A CLASH_MASK -p udp --dport 9993 -j RETURN
iptables -t mangle -A CLASH_MASK -m owner --uid-owner "$PROXY_BYPASS_USER" -j RETURN
iptables -t mangle -A CLASH_MASK -j RETURN -m mark --mark 0xff
iptables -t mangle -A CLASH_MASK -p udp -j MARK --set-mark "$PROXY_FWMARK"
iptables -t mangle -A CLASH_MASK -p tcp -j MARK --set-mark "$PROXY_FWMARK"

# REDIRECT OUTPUT CHAIN
iptables -t mangle -A OUTPUT -j CLASH_MASK


# 新建 DIVERT 规则，避免已有连接的包二次通过 TPROXY，理论上有一定的性能提升
# 同时解决无法访问已接管的私有地址(如：不在 localnetwork 中的地址) 的问题
iptables -t mangle -N DIVERT
iptables -t mangle -A DIVERT -j MARK --set-mark "$PROXY_FWMARK"
iptables -t mangle -A DIVERT -j ACCEPT
iptables -t mangle -I PREROUTING -p tcp -m socket -j DIVERT

# Apply QOS
fireqos start