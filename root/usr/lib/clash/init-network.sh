#!/bin/bash

if [ -n "${EN_MODE_TUN}" ]; then
    #TUN模式
    /usr/lib/clash/setup-tun.sh
else
    /usr/lib/clash/setup-tproxy.sh
fi
