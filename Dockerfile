FROM --platform=$TARGETPLATFORM alpine:3.17 AS rootfs-stage

# environment
ENV ROOTFS=/root-out

# args
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG RELEASE_TAG
ARG CLASH_VERSION
ARG CLASH_UPDATED_AT
ARG COMPILED_WITH
# set version for s6 overlay
ARG S6_OVERLAY_VERSION="3.1.5.0"
# ARG S6_OVERLAY_ARCH="x86_64"

# RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

RUN apk add --no-cache curl jq

WORKDIR $ROOTFS

# Prevent cache
# ADD https://api.github.com/repos/MetaCubeX/Clash.Meta/releases version.json
RUN set -eux; \
    \
    mkdir -p "${ROOTFS}/config/clash" \
        ${ROOTFS}/usr/local/bin \
    ; \
    \
    case ${RELEASE_TAG} in \
        "prerelease-alpha")  release_endpoint="tags/Prerelease-Alpha" ;; \
        "prerelease-meta")   release_endpoint="tags/Prerelease-Meta" ;; \
        *)                   release_endpoint="latest"; \
    esac; \
    \
    case ${TARGETPLATFORM} in \
        "linux/amd64")  architecture="linux-amd64"  ;; \
        "linux/arm64")  architecture="linux-arm64" ;; \
        "linux/arm/v7") architecture="linux-armv7" ;; \
    esac; \
    \
    res=$(curl -LSs "https://api.github.com/repos/MetaCubeX/Clash.Meta/releases/${release_endpoint}?per_page=1"); \
    assets=$(echo "${res}" | jq -r --arg architecture "$architecture" '.assets | map(select(.name | contains($architecture)))'); \
    if [ -z "${COMPILED_WITH}" ]; then \
        clash_download_url=$(echo "${assets}" | jq -r '. | sort_by(.name | length) | first | .browser_download_url' -); \
    else \
        clash_download_url=$(echo "${assets}" | jq -r --arg compiled_with "${COMPILED_WITH}" '.[] | select(.name | contains($compiled_with)) | .browser_download_url' -); \
    fi; \
    curl -L "${clash_download_url}" | gunzip - > "${ROOTFS}/usr/local/bin/clash"; \
    \
    cd "${ROOTFS}/config/clash"; \
    curl -L -O https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/release/country.mmdb; \
    curl -L -O https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/release/geoip.dat; \
    curl -L -O https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/release/geosite.dat; \
    \
# Add s6 overlay
    case ${TARGETPLATFORM} in \
        "linux/amd64")  s6_overlay_arch="x86_64" ;; \
        "linux/arm64")  s6_overlay_arch="aarch64" ;; \
        "linux/arm/v7") s6_overlay_arch="armhf" ;; \
        *) s6_overlay_arch="amd64" ;; \
    esac; \
    \
    add_s6_overlay() { \
        local overlay_version="${1}"; \
        local overlay_arch="${2}"; \
        curl -fsSL -o /tmp/s6-overlay.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${overlay_version}/s6-overlay-${overlay_arch}.tar.xz"; \
        tar -C "${ROOTFS}" -Jxpf "/tmp/s6-overlay.tar.xz"; \
        rm /tmp/s6-overlay.tar.xz; \
    }; \
    \
    add_s6_overlay "${S6_OVERLAY_VERSION}" "noarch"; \
    add_s6_overlay "${S6_OVERLAY_VERSION}" "${s6_overlay_arch}"; \
    \
# Add s6 optional symlinks
    add_s6_symlinks() { \
        local overlay_version="${1}"; \
        local overlay_arch="${2}"; \
        curl -fsSL -o /tmp/s6-overlay-symlinks.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${overlay_version}/s6-overlay-symlinks-${overlay_arch}.tar.xz"; \
        tar -C "${ROOTFS}" -Jxpf "/tmp/s6-overlay-symlinks.tar.xz"; \
        rm /tmp/s6-overlay-symlinks.tar.xz; \
    }; \
    \
    add_s6_symlinks "${S6_OVERLAY_VERSION}" "noarch"; \
    add_s6_symlinks "${S6_OVERLAY_VERSION}" "arch";

COPY root/. "${ROOTFS}/"

# Runtime stage
FROM --platform=$TARGETPLATFORM alpine:3.17 AS runtime
LABEL org.opencontainers.image.source https://silencebay@github.com/silencebay/clash-tproxy.git
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG FIREQOS_VERSION=latest
ARG FIREQOS_UPDATED_AT

# environment variables
ENV FAKE_IP_RANGE=198.18.0.1/16
# ENV DOCKER_HOST_INTERNAL=172.17.0.0/16,eth0
ENV DOCKER_HOST_INTERNAL=
ENV HOME="/config" \
  S6_CMD_WAIT_FOR_SERVICES_MAXTIME="0" \
  S6_VERBOSITY=1
# RUN echo "https://mirror.tuna.tsinghua.edu.cn/alpine/v3.11/main/" > /etc/apk/repositories
# RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

COPY --from=rootfs-stage /root-out/ /
# Seems like a nested hidden folder won't be copied by build-push-action@v4
# the file placed in /root/.config/clash/config.yaml.example will never be copy by `COPY root/. /`
# Just put the config.yaml out of that hidden folder and copy it.
# But We don't create another layer here, so the config.yaml.example file should have been copied from the builder
# COPY config.yaml.example /root/.config/clash/config.yaml

# fireqos
## iprange
WORKDIR /src
RUN set -eux; \
    \
    echo "**** create abc user and make our folders ****"; \
    # addgroup -g 1000 users; \
    # adduser -u 911 -D -h /config -s /bin/false abc; \
    adduser -u 911 -D -h /config -s /bin/bash abc; \
    addgroup abc users; \
    \
    echo "**** install system packages ****"; \
    buildDeps=" \
        jq \
        git \
        autoconf \
        automake \
        libtool \
        help2man \
        build-base \
    "; \
    runDeps=" \
        bash \
        mawk \
        iproute2 \
        ip6tables \
        iptables \
        ipset \
        libcap \
        # for debug
        curl \
        bind-tools \
        # eudev \
    "; \
    \
    apk add --no-cache --virtual .build-deps \
        $buildDeps \
        $runDeps \
    ; \
    \
## fireqos
    echo "**** build fireqos ****"; \
    git clone https://github.com/firehol/iprange; \
    cd iprange; \
    ./autogen.sh; \
    ./configure \
		--prefix=/usr \
		--sysconfdir=/etc/ssh \
		--datadir=/usr/share/openssh \
		--libexecdir=/usr/lib/ssh \
		--disable-man \
		--enable-maintainer-mode \
    ; \
    make; \
    make install; \
    \
    cd /src; \
    git clone https://github.com/firehol/firehol; \
    cd firehol; \
    tag=${FIREQOS_VERSION:-latest}; \
    [ "${tag}" = "latest" ] && tag=$(curl -SsL https://api.github.com/repos/firehol/firehol/releases/latest | jq -r '.tag_name'); \
    git checkout $tag; \
    ./autogen.sh; \
    ./configure \
        CHMOD=chmod \
		--prefix=/usr \
		--sysconfdir=/etc \
		--disable-firehol \
		--disable-link-balancer \
		--disable-update-ipsets \
		--disable-vnetbuild \
        --disable-doc \
        --disable-man \
    ; \
    make; \
    make install; \
    \
    apk add --no-network --virtual .run-deps \
        $runDeps \
    ; \
    apk del .build-deps; \
    rm -rf /src; \
    \
    echo "**** setup permisions ****"; \
    chown -R abc:users /config; \
    chmod a+x /app/* /usr/local/bin/* /usr/lib/clash/*; \
# dumped by `pscap` of package `libcap-ng-utils`
    setcap cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,cap_net_raw,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap,cap_net_admin=+ep /usr/local/bin/clash

WORKDIR $HOME

ENTRYPOINT ["/init"]
