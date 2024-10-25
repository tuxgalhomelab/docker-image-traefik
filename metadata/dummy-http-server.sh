#!/usr/bin/env bash
set -E -e -o pipefail

# Load the helpers to set up the context.
script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source /opt/homelab/scripts/all

respondToNextRequest() {
    echo -ne "HTTP/1.0 200 OK\r\n\r\n"
}

runServerLoop() {
    local listen_addr="${1:?}"
    local listen_port="${2:?}"
    while true; do
        respondToNextRequest | nc -N -l ${listen_addr:?} ${listen_port:?}
    done
}

logInfo "Starting HTTP server ..."
logInfo "HTTP server listening on ${1:?}:${2:?}"
runServerLoop "$@"
