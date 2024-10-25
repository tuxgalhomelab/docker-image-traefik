#!/usr/bin/env bash
set -E -e -o pipefail

traefik_static_config="/data/traefik/config/static/traefik.yaml"
traefik_dynamic_config="/data/traefik/config/dynamic/backends.yaml"

set_umask() {
    # Configure umask to allow write permissions for the group by default
    # in addition to the owner.
    umask 0002
}

generate_traefik_static_config() {
    echo "Generating Traefik static configuration at ${traefik_static_config:?}"
    mkdir -p "$(dirname "${traefik_static_config:?}")"
    cat << EOF > ${traefik_static_config:?}
log:
  level: INFO
accesslog: {}
global:
  checkNewVersion: true
  sendAnonymousUsage: false
api:
  debug: true
  dashboard: true
  disableDashboardAd: true
entrypoints:
  http-proxy:
    address: :8080
    asDefault: true
providers:
  file:
    directory: $(dirname "${traefik_dynamic_config:?}")
    watch: true
EOF
}

generate_traefik_dynamic_config() {
    echo "Generating Traefik dynamic configuration at ${traefik_dynamic_config:?}"
    mkdir -p "$(dirname "${traefik_dynamic_config:?}")"
    cat << EOF > ${traefik_dynamic_config:?}
http:
  routers:
    to-local-backend:
      rule: 'HostRegexp(\`^.*$\`)'
      service: local-backend
  services:
    local-backend:
      loadBalancer:
        servers:
          - url: http://localhost:8081/
EOF
}

setup_traefik_config() {
    echo "Checking for existing Traefik config ..."
    echo

    if [ -f "${traefik_static_config:?}" ]; then
        echo "Existing Traefik static configuration \"${traefik_static_config:?}\" found"
    else
        generate_traefik_static_config
        generate_traefik_dynamic_config
    fi
    echo
}

start_traefik() {
    echo "Starting Traefik ..."
    echo

    exec traefik --configFile ${traefik_static_config:?}
}

set_umask
setup_traefik_config
start_traefik
