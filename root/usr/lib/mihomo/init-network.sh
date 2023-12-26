#!/bin/bash

if [ -n "${EN_MODE_TUN}" ]; then
    #TUN模式
    /usr/lib/mihomo/setup-tun.sh
else
    /usr/lib/mihomo/setup-tproxy.sh
fi
