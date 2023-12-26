#!/bin/bash

set -e

if [ -n "$EN_MODE_TUN" ]; then
    #TUN模式
    /usr/lib/mihomo/setup-tun.sh &
else
    /usr/lib/mihomo/setup-tproxy.sh &
fi

# 开启转发，需要 privileged
# Deprecated! 容器默认已开启
# echo "1" > /proc/sys/net/ipv4/ip_forward

if [ ! -e '/mihomo_config/config.yaml' ]; then
    echo "init /mihomo_config/config.yaml"
    cp  /root/.config/mihomo/config.yaml /mihomo_config/config.yaml
fi

if [ ! -e '/mihomo_config/Country.mmdb' ]; then
    echo "init /mihomo_config/Country.mmdb"
    cp  /root/.config/mihomo/Country.mmdb /mihomo_config/Country.mmdb
fi

exec "$@"