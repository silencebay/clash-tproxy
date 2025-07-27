#!/bin/bash

# =============================================================================
# TProxy Setup Script - Traffic Marking System
# =============================================================================
# This script sets up transparent proxy rules using nftables.
#
# MARKING SYSTEM DESIGN:
# ----------------------
# 32-bit mark field is divided into two parts to avoid conflicts:
#
# Low 16 bits (0x0000FFFF): TProxy system
#   - PROXY_FWMARK (0x1): Marks traffic for transparent proxy
#   - PROXY_ROUTING_MARK (0x2): Marks mihomo process traffic for bypass
#
# High 16 bits (0xFFFF0000): Available for other systems (optional)
#   - 0x10000+: Can be used by traffic classification systems (e.g., QoS)
#
# COMPATIBILITY:
# --------------
# - Uses bit masking (& 0xFFFF) to check only TProxy bits
# - Preserves marks in high bits when setting TProxy marks
# - Allows coexistence with other marking systems (e.g., QoS, traffic shaping)
# =============================================================================

source /usr/lib/mihomo/common.sh

bypass_ip4=$(get_bypass_ip4)
[ -n "${bypass_ip4}" ] &&
  bypass_ip4_rule="ip daddr { $(join ", " ${bypass_ip4}) } meta mark != ${PROXY_FWMARK} accept comment \"Bypass IPv4 addresses\""

bypass_ip6=$(get_bypass_ip6)
[ -n "${bypass_ip6}" ] &&
  bypass_ip6_rule="ip6 daddr { $(join ", " ${bypass_ip6}) } meta mark != ${PROXY_FWMARK} accept comment \"Bypass IPv6 addresses\""

takeover_ip4=$(get_takeover_ip4)
[ -n "${takeover_ip4}" ] &&
  takeover_ip4_rule="ip daddr { $(join ", " ${takeover_ip4}) } meta mark set ${PROXY_FWMARK} comment \"Takeover IPv4 addresses\""

takeover_ip6=$(get_takeover_ip6)
[ -n "${takeover_ip6}" ] &&
  takeover_ip6_rule="ip6 daddr { $(join ", " ${takeover_ip6}) } meta mark set ${PROXY_FWMARK} comment \"Takeover IPv6 addresses\""

set_rules() {
  ip rule add fwmark "${PROXY_FWMARK}" table 104
  #ip route add local default dev lo table 104
  ip route add local 0.0.0.0/0 dev lo table 104

  if test "${ENABLE_IPV6_ROUTE:-false}" == true; then
    ip -6 rule add fwmark "${PROXY_FWMARK}" table 106
    #ip -6 route add local default dev lo table 106
    ip -6 route add local ::/0 dev lo table 106
  fi

  nft -f - <<EOF
table inet $NFT_TABLE {
  chain $NFT_PREROUTING_CHAIN {
    type filter hook prerouting priority mangle; policy accept;
    #meta l4proto { tcp, udp } th dport 53 tproxy to :$PROXY_TPROXY_PORT accept comment "Transparent DNS proxy"
    meta l4proto { tcp, udp } th dport 53 accept
    tcp dport $PROXY_TPROXY_PORT reject with tcp reset comment "Rejecting direct access to tproxy port"
    udp dport $PROXY_TPROXY_PORT reject with icmp port-unreachable comment "Rejecting direct access to tproxy port"
    $takeover_ip4_rule
    $takeover_ip6_rule
    $bypass_ip4_rule
    $bypass_ip6_rule
    # BYPASS CHECK: Check if traffic is from mihomo process
    # Uses bit mask to check only low 16 bits, allowing other systems to use high 16 bits
    meta mark and 0xFFFF == ${PROXY_ROUTING_MARK} accept comment "Bypass traffic from mihomo process (check low 16 bits only)"

    # ESTABLISHED CONNECTIONS: Bypass already established transparent proxy connections
    meta l4proto tcp socket transparent 1 meta mark set $PROXY_FWMARK accept comment "Bypass established transparent proxy connections"

    # TRANSPARENT PROXY: Redirect traffic to mihomo and mark it
    # Preserves existing marks in high 16 bits (e.g., QoS marks) while setting TProxy mark in low 16 bits
    meta l4proto { tcp, udp } tproxy to :$PROXY_TPROXY_PORT meta mark set ((meta mark and 0xFFFF0000) | $PROXY_FWMARK) comment "Set TProxy mark, preserve high bits"
  }

  chain $NFT_OUTPUT_CHAIN {
    type route hook output priority mangle; policy accept;
    oifname != eth0 accept comment "Process only traffic from specified network interface (bypass traffic internal to this machine, e.g., loopback, etc.)"
    # OUTPUT CHAIN: Process traffic originating from this machine

    # BYPASS CHECK: Same as prerouting - check mihomo process traffic
    meta mark and 0xFFFF == ${PROXY_ROUTING_MARK} accept comment "Bypass traffic from mihomo process (check low 16 bits only)"

    # USER BYPASS: Bypass traffic from mihomo user (alternative to mark-based bypass)
    meta skuid "${PROXY_BYPASS_USER_ID}" accept comment "Bypass traffic originated from user abc (owner of mihomo process)"

    # DNS BYPASS: Let DNS traffic pass through normally
    #meta l4proto { tcp, udp } th dport 53 meta mark set $PROXY_FWMARK accept comment "DNS rerouting to prerouting"
    meta l4proto { tcp, udp } th dport 53 accept

    # NETBIOS BYPASS: Bypass local network discovery traffic
    udp dport { netbios-ns, netbios-dgm, netbios-ssn } accept comment "Bypass NBNS traffic"

    # IP-BASED RULES: Apply takeover and bypass rules
    $takeover_ip4_rule
    $takeover_ip6_rule
    $bypass_ip4_rule
    $bypass_ip6_rule

    # REROUTE TO PREROUTING: Mark other traffic for processing in prerouting chain
    # Preserves existing marks in high 16 bits (e.g., QoS) while adding TProxy mark for routing
    meta l4proto { tcp, udp } meta mark set ((meta mark and 0xFFFF0000) | $PROXY_FWMARK) comment "Reroute traffic to prerouting, preserve high bits"
  }
}
EOF

  if test "${ENABLE_REDIRECT_DNS:-false}" == true; then
    nft -f - <<EOF
table inet $NFT_TABLE {
  chain dstnat {
    type nat hook prerouting priority dstnat; policy accept;
    meta l4proto { tcp, udp } th dport 53 redirect to :53 comment "mihomo DNS Hijack"
  }
}
EOF
  fi
}

set_dns() {
  # > LOCAL MACHINE DNS
  log "[DNS] Setting local machine dns"
  while true; do
    log "[DNS] Waiting for mihomo getting ready"
    if test "${ENABLE_IPV6_ROUTE:-false}" == true; then
      curl -Ss http://www.tsinghua.edu.cn >/dev/null
    else
      curl -4Ss http://www.tsinghua.edu.cn >/dev/null
    fi

    [ $? -eq 0 ] && break
    sleep 1
  done
  while cat /proc/mounts | grep overlay | grep /etc/resolv.conf &>/dev/null; do umount /etc/resolv.conf &>/dev/null; done
  temp_resolv_conf=$(mktemp)
  chmod 0644 $temp_resolv_conf
  mount -o bind $temp_resolv_conf /etc/resolv.conf
  rm -f $temp_resolv_conf
  echo "# Generated by setup-tproxy.sh at $(date '+%F %T')" >/etc/resolv.conf
  echo "nameserver 127.0.0.1" >>/etc/resolv.conf
}

set_docker_host_internal() {
  # > Handle DOCKER_HOST_INTERNAL
  log "[DOCKER_HOST_INTERNAL] setting route"
  source /usr/lib/mihomo/setup-docker-host-route.sh
}

main() {
  set_rules
  set_dns
  set_docker_host_internal
  log "Done"
}

main
