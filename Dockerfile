# syntax=docker/dockerfile:1

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG

ARG GO_IMAGE_NAME
ARG GO_IMAGE_TAG
FROM ${GO_IMAGE_NAME}:${GO_IMAGE_TAG} AS builder

ARG NVM_VERSION
ARG NVM_SHA256_CHECKSUM
ARG IMAGE_NODEJS_VERSION
ARG YARN_VERSION
ARG TRAEFIK_VERSION

COPY scripts/start-traefik.sh /scripts/
COPY patches /patches

# hadolint ignore=DL4006,SC3040,SC3009
RUN \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    && homelab install git patch \
    && homelab install-node \
        ${NVM_VERSION:?} \
        ${NVM_SHA256_CHECKSUM:?} \
        ${IMAGE_NODEJS_VERSION:?} \
    # Download traefik repo. \
    && homelab download-git-repo \
        https://github.com/traefik/traefik \
        ${TRAEFIK_VERSION:?} \
        /root/traefik-build \
    && pushd /root/traefik-build \
    # Apply the patches. \
    && (find /patches -iname *.diff -print0 | sort -z | xargs -0 -r -n 1 patch -p2 -i) \
    && popd \
    && source /opt/nvm/nvm.sh \
    && npm install -g yarn@${YARN_VERSION:?} && corepack enable \
    # Build Traefik Web UI. \
    && export WEBUI_DIR="/webui-dist" \
        && export VITE_APP_BASE_URL="" \
        && export VITE_APP_BASE_API_URL="/api" \
        && mkdir -p ${WEBUI_DIR:?} \
        && cp /root/traefik-build/webui/{package.json,yarn.lock,.yarnrc.yml} ${WEBUI_DIR:?}/ \
        && pushd ${WEBUI_DIR:?} \
        && yarn workspaces focus --all --production \
        && cp -a /root/traefik-build/webui/. ${WEBUI_DIR:?}/ \
        # We are manually replicating the commands from the build:prod script in \
        # https://github.com/traefik/traefik/blob/master/webui/package.json \
        # since yarn test fails with a timeout for arm64 builds. \
        && (yarn test || true) && yarn tsc && yarn lint && yarn build \
        && popd \
        && cp -a ${WEBUI_DIR:?}/static/. /root/traefik-build/webui/static/ \
    # Build Traefik. \
    && pushd /root/traefik-build \
    && CGO_ENABLED=0 GOGC=off GOOS=linux \
        go build -ldflags "-s -w \
            -X github.com/traefik/traefik/v3/pkg/version.Version=$(git describe --abbrev=0 --tags --exact-match) \
            -X github.com/traefik/traefik/v3/pkg/version.Codename=cheddar \
            -X github.com/traefik/traefik/v3/pkg/version.BuildDate=$(date -u '+%Y-%m-%d_%I:%M:%S%p')" \
        -o ./traefik \
        ./cmd/traefik \
    && popd \
    # Copy the build artifacts. \
    && mkdir -p /output/{bin,scripts} \
    && cp /root/traefik-build/traefik /output/bin \
    && cp /scripts/* /output/scripts

FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

ARG USER_NAME
ARG GROUP_NAME
ARG USER_ID
ARG GROUP_ID
ARG TRAEFIK_VERSION

# hadolint ignore=DL4006,SC2086,SC3009
RUN --mount=type=bind,target=/traefik-build,from=builder,source=/output \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    # Create the user and the group. \
    && homelab add-user \
        ${USER_NAME:?} \
        ${USER_ID:?} \
        ${GROUP_NAME:?} \
        ${GROUP_ID:?} \
        --create-home-dir \
    && mkdir -p /opt/traefik-${TRAEFIK_VERSION:?}/bin /data/traefik/{config,data} \
    && cp /traefik-build/bin/traefik /opt/traefik-${TRAEFIK_VERSION:?}/bin \
    && ln -sf /opt/traefik-${TRAEFIK_VERSION:?} /opt/traefik \
    && ln -sf /opt/traefik/bin/traefik /opt/bin/traefik \
    # Copy the start-traefik.sh script. \
    && cp /traefik-build/scripts/start-traefik.sh /opt/traefik/ \
    && ln -sf /opt/traefik/start-traefik.sh /opt/bin/start-traefik \
    # Set up the permissions. \
    && chown -R ${USER_NAME:?}:${GROUP_NAME:?} \
        /opt/traefik-${TRAEFIK_VERSION:?} \
        /opt/traefik \
        /opt/bin/{traefik,start-traefik} \
        /data/traefik \
    # Clean up. \
    && homelab cleanup

# Expose both the HTTP and the HTTPS ports used by Traefik.
EXPOSE 80
EXPOSE 443

ENV USER=${USER_NAME}
USER ${USER_NAME}:${GROUP_NAME}
WORKDIR /home/${USER_NAME}

CMD ["start-traefik"]
STOPSIGNAL SIGTERM
