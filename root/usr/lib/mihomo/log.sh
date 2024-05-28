#!/bin/bash

PROGRAM_NAME="$(basename "${0}")"

logdate() {
  date "+%Y-%m-%d %H:%M:%S"
}

log() {
  local status="${1}"
  shift

  echo >&2 "$(logdate): ${PROGRAM_NAME}: ${status}: ${*}"

}

warning() {
  log WARNING "${@}"
}

error() {
  log ERROR "${@}"
}

info() {
  log INFO "${@}"
}

fatal() {
  log FATAL "${@}"
  exit 1
}
