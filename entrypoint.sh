#!/bin/bash

set -e

/usr/lib/clash/setup-tun.sh &

#开启转发
echo "1" > /proc/sys/net/ipv4/ip_forward

if [ ! -e '/clash_config/config.yaml' ]; then
    echo "init /clash_config/config.yaml"
    cp  /root/.config/clash/config.yaml /clash_config/config.yaml
fi

if [ ! -e '/clash_config/Country.mmdb' ]; then
    echo "init /clash_config/Country.mmdb"
    cp  /root/.config/clash/Country.mmdb /clash_config/Country.mmdb
fi

exec "$@"