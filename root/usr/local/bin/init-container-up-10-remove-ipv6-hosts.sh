#!/bin/bash

if [[ "${REMOVE_IPV6_HOSTS,,}" = "true" ]]; then
    echo "$(awk -v host="$(cat /etc/hostname)" '$2 == host && $1 ~ /^[0-9a-fA-F:]+$/ {next} 1' /etc/hosts)" > /etc/hosts
fi
