#!/bin/bash

# =============================================================================
# Common variables and functions for mihomo scripts
# =============================================================================
#
# TRAFFIC MARKING SYSTEM OVERVIEW:
# ---------------------------------
# This project uses a 32-bit traffic marking system designed to support both
# transparent proxy (TProxy) functionality and Quality of Service (QoS) classification.
#
# BIT ALLOCATION:
# ---------------
# 32-bit mark field is divided into two independent parts:
#
# Low 16 bits (0x0000FFFF): TProxy System
#   - PROXY_FWMARK (0x1): Marks traffic for transparent proxy routing
#   - PROXY_ROUTING_MARK (0x2): Marks mihomo process traffic for bypass
#
# High 16 bits (0xFFFF0000): Custom Marking (optional)
#   - 0x10000: Gaming devices (highest priority)
#   - 0x20000: Streaming devices (high priority)
#   - 0x30000: Work devices (medium priority)
#   - 0x40000: Mobile devices (standard priority)
#   - 0x50000: IoT devices (low priority)
#
# COMPATIBILITY DESIGN:
# ---------------------
# - TProxy checks use bit masking (& 0xFFFF) to ignore custom bits
# - Custom marking uses OR operations to preserve TProxy bits
# - Both systems can operate independently and simultaneously
# - No conflicts between TProxy routing and custom classification
#
# EXAMPLE COMBINED MARKING:
# -------------------------
# Gaming device packet: 0x10001 = 0x10000 (Custom: Gaming) | 0x1 (TProxy: Marked)
# - TProxy sees: 0x10001 & 0xFFFF = 0x1 ✓ (correctly identified)
# - Custom sees: 0x10001 & 0x10000 = 0x10000 ✓ (correctly classified)
# =============================================================================

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
      "fc00::/7"
      "ff00::/8")
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
# =============================================================================
# TProxy System Configuration
# =============================================================================
# These marks use the low 16 bits (0x0000FFFF) of the 32-bit mark field

readonly PROXY_BYPASS_USER_ID="911"
# readonly PROXY_BYPASS_CGROUP="0x100000"
readonly PROXY_TPROXY_PORT="${TPROXY_PORT:-7893}"

# PROXY_FWMARK: Marks traffic that should be processed by transparent proxy
# Used by routing rules to direct traffic to mihomo
readonly PROXY_FWMARK="0x1"

readonly PROXY_ROUTE_TABLE="0x1"

# PROXY_ROUTING_MARK: Marks traffic from mihomo process itself
# Used to prevent infinite loops by bypassing mihomo's own traffic
# Default 0x2 (can be overridden by ROUTING_MARK environment variable)
readonly PROXY_ROUTING_MARK="${ROUTING_MARK:-0x2}"

# =============================================================================
# TProxy Mark Validation Functions
# =============================================================================

# Validate that TProxy marks stay within low 16 bits
validate_tproxy_marks() {
    local mark_name="$1"
    local mark_value="$2"
    local mark_dec

    # Convert hex to decimal if needed
    if [[ "$mark_value" =~ ^0x[0-9a-fA-F]+$ ]]; then
        mark_dec=$((mark_value))
    else
        mark_dec="$mark_value"
    fi

    # Check if mark exceeds low 16 bits (0xFFFF = 65535)
    if [[ $mark_dec -gt 65535 ]]; then
        echo "ERROR: TProxy mark $mark_name ($mark_value) exceeds low 16 bits limit (0xFFFF)" >&2
        echo "TProxy marks must stay within 0x0000-0xFFFF range to avoid conflicts" >&2
        return 1
    fi

    # Check if mark conflicts with high 16 bits
    local high_bits=$((mark_dec & 0xFFFF0000))
    if [[ $high_bits -ne 0 ]]; then
        echo "ERROR: TProxy mark $mark_name ($mark_value) uses high 16 bits" >&2
        echo "High 16 bits are reserved for custom marking" >&2
        return 1
    fi

    return 0
}

# Validate all TProxy marks on script load
validate_all_tproxy_marks() {
    local validation_failed=false

    # Validate PROXY_FWMARK
    if ! validate_tproxy_marks "PROXY_FWMARK" "$PROXY_FWMARK"; then
        validation_failed=true
    fi

    # Validate PROXY_ROUTING_MARK
    if ! validate_tproxy_marks "PROXY_ROUTING_MARK" "$PROXY_ROUTING_MARK"; then
        validation_failed=true
    fi

    if [[ "$validation_failed" == "true" ]]; then
        echo "FATAL: TProxy mark validation failed. Please fix the configuration." >&2
        return 1
    fi

    return 0
}

readonly PROXY_DNS_PORT="1053"
readonly PROXY_TUN_DEVICE_NAME="utun"
readonly NFT_TABLE="mihomo"
readonly NFT_PREROUTING_CHAIN="prerouting"
readonly NFT_OUTPUT_CHAIN="output"

# =============================================================================
# Validate TProxy marks on script load
# =============================================================================
# This ensures that any configuration errors are caught early
if ! validate_all_tproxy_marks; then
    exit 1
fi
