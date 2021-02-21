#!/bin/bash

set -e

if [ -n "$EN_MODE_TUN" ]; then
    #TUN模式
    /usr/lib/clash/setup-tun.sh &
else
    /usr/lib/clash/setup-tproxy.sh &
fi

# 开启转发，需要 privileged
# Deprecated! 容器默认已开启
# echo "1" > /proc/sys/net/ipv4/ip_forward

if [ ! -e '/clash_config/config.yaml' ]; then
    echo "init /clash_config/config.yaml"
    cp  /root/.config/clash/config.yaml /clash_config/config.yaml
fi

if [ ! -e '/clash_config/Country.mmdb' ]; then
    echo "init /clash_config/Country.mmdb"
    cp  /root/.config/clash/Country.mmdb /clash_config/Country.mmdb
fi

exec "$@"