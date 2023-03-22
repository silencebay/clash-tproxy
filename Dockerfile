FROM --platform=$TARGETPLATFORM golang:alpine AS builder
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG RELEASE_TAG
ARG CLASH_VERSION
ARG CLASH_UPDATED_AT
ARG COMPILED_WITH

# RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

RUN apk add --no-cache curl jq

WORKDIR /go

# Prevent cache
# ADD https://api.github.com/repos/MetaCubeX/Clash.Meta/releases version.json
RUN set -eux; \
    \
    mkdir artifact; \
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
    curl -L "${clash_download_url}" | gunzip - > artifact/clash;

RUN set -eux; \
    \
    cd /go/artifact; \
    curl -L -O https://raw.githubusercontent.com/Loyalsoldier/geoip/release/Country.mmdb; \
    curl -L -O https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat; \
    curl -L -O https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat;

COPY config.yaml.example /go/artifact/config.yaml

FROM --platform=$TARGETPLATFORM alpine:3.13 AS runtime
LABEL org.opencontainers.image.source https://silencebay@github.com/silencebay/clash-tproxy.git
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG FIREQOS_VERSION=latest
ARG FIREQOS_UPDATED_AT
ENV FAKE_IP_RANGE=198.18.0.1/16
# ENV DOCKER_HOST_INTERNAL=172.17.0.0/16,eth0
ENV DOCKER_HOST_INTERNAL=

# RUN echo "https://mirror.tuna.tsinghua.edu.cn/alpine/v3.11/main/" > /etc/apk/repositories
# RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

COPY --from=builder /go/artifact/* /artifact/
COPY root/. /
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
    mkdir -p /root/.config/clash; \
    mv /artifact/clash /usr/local/bin/; \
    mv /artifact/* /root/.config/clash/; \
    \
    buildDeps=" \
        jq \
        git \
        autoconf \
        automake \
        libtool \
        help2man \
        build-base \
        bash \
        iproute2 \
        ip6tables \
        iptables \
    "; \
    runDeps=" \
        bash \
        iproute2 \
        ip6tables \
        iptables \
        ipset \
        libcap \
        # for debug
        curl \
        bind-tools \
        bash-doc \
        bash-completion \
        # eudev \
    "; \
    \
    apk add --no-cache --virtual .build-deps \
        $buildDeps \
        $runDeps \
    ; \
    \
    \
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
    \
    ## fireqos
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
    \
    # clash
    \
    chmod a+x /usr/local/bin/* /usr/lib/clash/*; \
    # dumped by `pscap` of package `libcap-ng-utils`
    setcap cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,cap_net_raw,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap,cap_net_admin=+ep /usr/local/bin/clash

WORKDIR /clash_config

ENTRYPOINT ["entrypoint.sh"]
CMD ["su", "-s", "/bin/bash", "-c", "/usr/local/bin/clash -d /clash_config", "nobody"]
