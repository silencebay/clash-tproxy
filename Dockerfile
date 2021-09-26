FROM --platform=$TARGETPLATFORM golang:alpine AS builder
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG CLASH_VERSION

# RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

RUN apk add --no-cache curl jq

WORKDIR /go

# Prevent cache
# ADD https://api.github.com/repos/Dreamacro/clash/releases/tags/premium version.json
RUN set -eux; \
    \
    if [ "${TARGETPLATFORM}" = "linux/amd64" ]; then architecture="linux-amd64" ; fi; \
    if [ "${TARGETPLATFORM}" = "linux/arm64" ]; then architecture="linux-armv8" ; fi; \
    if [ "${TARGETPLATFORM}" = "linux/arm/v7" ] ; then architecture="linux-armv7" ; fi; \
    clash_download_url=$(curl -L https://api.github.com/repos/Dreamacro/clash/releases/tags/premium | jq -r --arg architecture "$architecture" '.assets[] | select (.name | contains($architecture)) | .browser_download_url' -); \
    curl -L $clash_download_url | gunzip - > clash;

RUN set -eux; \
    \
    curl -L -O https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb;


FROM --platform=$TARGETPLATFORM alpine:3.13 AS runtime
LABEL org.opencontainers.image.source https://silencebay@github.com/silencebay/clash-tproxy.git
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG FIREQOS_VERSION=latest
ARG FIREQOS_TARGET_COMMITISH

# RUN echo "https://mirror.tuna.tsinghua.edu.cn/alpine/v3.11/main/" > /etc/apk/repositories

COPY --from=builder /go/clash /usr/local/bin/
COPY --from=builder /go/Country.mmdb /root/.config/clash/
COPY config.yaml.example /root/.config/clash/config.yaml
COPY entrypoint.sh /usr/local/bin/
COPY scripts/* /usr/lib/clash/
COPY fireqos.conf /etc/firehol/fireqos.conf

# RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

# fireqos
## iprange
WORKDIR /src
RUN set -eux; \
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
    if [ "${tag}" = "latest" ]; then tag=$(curl -L --silent https://api.github.com/repos/firehol/firehol/releases/latest | jq -r .tag_name); fi; \
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
