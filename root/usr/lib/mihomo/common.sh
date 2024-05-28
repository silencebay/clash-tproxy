#!/bin/bash

source /usr/lib/mihomo/log.sh

is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]+)?$ ]]
}

is_ipv6() {
  [[ "$1" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}(\/[0-9]+)?$ ]]
}

get_host_ip6() {
  echo $(ip -6 addr show | awk '/inet6/ {print $2}' | sed 's/\/.*//')
}

get_host_ip4() {
  # ips=$(hostname -i)
  echo $(ip -4 addr show | awk '/inet/ {print $2}' | sed 's/\/.*//')
}

get_bypass_ip4() {
  local bypass_ip4=()
  if [ -n "${BYPASS_IP4}" ]; then
    bypass_ip4=$(get_valid_ip4_from_comma_string "${BYPASS_IP4}")
  else
    bypass_ip4=(
      "127.0.0.0/8"
      "10.0.0.0/8"
      "100.64.0.0/10"
      "169.254.0.0/16"
      "172.16.0.0/12"
      "192.168.0.0/16"
      "224.0.0.0/4"
      "240.0.0.0/4"
      "255.255.255.255/32")
  fi
  # validate bypass_ip4 items
  echo ${bypass_ip4[*]} $(get_host_ip4)
}

get_bypass_ip6() {
  local bypass_ip6=()
  if [ -n "${BYPASS_IP6}" ]; then
    bypass_ip6=$(get_valid_ip6_from_comma_string "${BYPASS_IP6}")
  else
    bypass_ip6=(
      "::1/128"
      "fe80::/10"
      "fc00::/7")
  fi
  echo ${bypass_ip6[*]} $(get_host_ip6)
}

get_takeover_ip4() {
  if [ -z "${TAKEOVER_IP4}" ]; then
    return 0
  fi
  echo $(get_valid_ip4_from_comma_string "${TAKEOVER_IP4}")
}

get_takeover_ip6() {
  if [ -z "${TAKEOVER_IP6}" ]; then
    return 0
  fi
  echo $(get_valid_ip6_from_comma_string "${TAKEOVER_IP6}")
}

#######################################
# Returns a valid IPv4 address string from a comma-separated string of IPv4 addresses.
#
# Arguments:
#   - ${1} (string): The comma-separated string of IPv4 addresses.
#
# Outputs:
#   - (string): The valid IPv4 addresses separated by spaces.
#######################################
get_valid_ip4_from_comma_string() {
  local r=()
  for item in $(comma2space "${1}"); do
    if ! is_ipv4 "${item}"; then
      warning "Invalid ip4 item: ${item}"
    else
      r+=("${item}")
    fi
  done
  echo "${r[@]}"
}

#######################################
# Returns a valid IPv6 address string from a comma-separated string of IPv6 addresses.
#
# Arguments:
#   - ${1} (string): The comma-separated string of IPv6 addresses.
#
# Outputs:
#   - (string): The valid IPv6 addresses separated by spaces.
#######################################
get_valid_ip6_from_comma_string() {
  local r=()
  for item in $(comma2space "${1}"); do
    if ! is_ipv6 "${item}"; then
      warning "Invalid ip6 item: ${item}"
    else
      r+=("${item}")
    fi
  done
  echo "${r[@]}"
}

comma2space() {
  echo "${1//,/ }"
}

space2comma() {
  echo "${1// /,}"
}

#######################################
# Joins the given string into a single string with the specified separator.
#
# Arguments:
#   - separator: The character or string used to separate the arguments.
#   - string: The string to be joined.
#
# Outputs:
#   The joined string.
#######################################
join() {
  local separator="$1"
  shift
  local joined=""
  awk -v sep="$separator" 'BEGIN { joined = ARGV[1]; for (i = 2; i < ARGC; i++) { joined = joined sep ARGV[i]; } print joined; exit; }' "$@"
}

#######################################
# Joins the given arguments into a single string with the specified separator.
#
# Parameters:
# - separator: The character or string used to separate the arguments.
# - arguments: The arguments to be joined.
#
# Outputs:
#   The joined string.
#######################################
join_args() {
  local separator="$1"
  shift
  awk -v sep="$separator" 'BEGIN { joined = ARGV[1]; for (i = 2; i < ARGC; i++) { joined = joined sep ARGV[i]; } print joined; exit; }' "$@"
}

readonly PROXY_BYPASS_USER="abc"
readonly PROXY_BYPASS_USER_ID="911"
# readonly PROXY_BYPASS_CGROUP="0x100000"
readonly PROXY_TPROXY_PORT="${TPROXY_PORT:-7893}"
readonly PROXY_FWMARK="0x1"
readonly PROXY_ROUTE_TABLE="0x1"
readonly PROXY_ROUTING_MARK="${ROUTING_MARK:-6666}"
readonly PROXY_DNS_PORT="1053"
readonly PROXY_TUN_DEVICE_NAME="utun"
readonly NFT_TABLE="mihomo"
readonly NFT_PREROUTING_CHAIN="prerouting"
readonly NFT_OUTPUT_CHAIN="output"
