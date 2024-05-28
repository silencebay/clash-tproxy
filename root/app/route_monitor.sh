#!/bin/bash
set -eu

. /usr/lib/mihomo/common.sh

is_ipv4() {
  ! is_ipv6 "$1" && return 0 || return 1
}

is_ipv6() {
  echo "$1" | grep -q '::' && return 0 || return 1
}

find_output_chain_handles() {
  local search_string=$1

  echo $(nft -a list chain inet "$NFT_TABLE" "$NFT_OUTPUT_CHAIN" 2>&1 | grep "$search_string" | awk -F '# handle ' '{print$2}')
}

chain_exists() {
  local search_string=$1

  nft -a list chain inet "$NFT_TABLE" "$search_string" >/dev/null 2>&1
}

extract_network_from_change() {
  local change=$1

  echo "$change" | awk '{print $1}'
}

get_insert_position() {
  echo $(find_output_chain_handles "." | awk '{print $(NF-1)}')
}

add_bypass_rule4() {
  local network=$1
  local position=$2

  nft add rule inet mihomo "$NFT_OUTPUT_CHAIN" position "$position" ip daddr "$network" meta mark != ${PROXY_FWMARK} accept comment \"Bypass IPv4 addresses\"
}

add_bypass_rule6() {
  local network=$1
  local position=$2

  nft add rule inet mihomo "$NFT_OUTPUT_CHAIN" position "$position" ip6 daddr "$network" meta mark != ${PROXY_FWMARK} accept comment \"Bypass IPv6 addresses\"
}

add_bypass_rule() {
  local network=$1
  local handles
  local position

  chain_exists "$NFT_OUTPUT_CHAIN" || return

  handles=$(find_output_chain_handles "$network")
  [ -n "$handles" ] && return

  position=$(get_insert_position)
  if [ -z "$position" ]; then
    warning "Can't find insert position"
    return
  fi

  is_ipv6 "$1" && add_bypass_rule6 "$1" "$position" || add_bypass_rule4 "$1" "$position"
}

remove_bypass_rule() {
  local network=$1

  chain_exists "$NFT_OUTPUT_CHAIN" || return

  handles=$(find_output_chain_handles "$network")
  [ -z "$handles" ] && return
  handles=($handles)

  for handle in $handles; do
    info "$handle"
    nft delete rule inet "$NFT_TABLE" "$NFT_OUTPUT_CHAIN" handle "$handle"
  done
}

init() {
  # Add default bypass rules for IPv4 and IPv6
  ip route | grep -v '^default' | while read -r line; do
    line=$(echo "$line" | awk '{print $1}')
    add_bypass_rule "$line"
  done

  ip -6 route | grep -v '^default' | while read -r line; do
    line=$(echo "$line" | awk '{print $1}')
    add_bypass_rule "$line"
  done
}

mon() {
  ip monitor route | while read -r line; do
    case "$line" in
    Deleted*)
      line=$(echo "$line" | awk '{print $2}')
      network=$(extract_network_from_change "$line")
      remove_bypass_rule "$network"
      info "Removed bypass rule for $network"
      ;;
    *)
      network=$(extract_network_from_change "$line")
      add_bypass_rule "$network"
      info "Added bypass rule for $network"
      ;;
    esac
  done
}

main() {
  init
  mon
}

main
