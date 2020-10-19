FROM --platform=$TARGETPLATFORM golang:alpine AS builder
ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN apk add --no-cache curl jq

WORKDIR /go
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

FROM --platform=$TARGETPLATFORM alpine AS runtime
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# RUN echo "https://mirror.tuna.tsinghua.edu.cn/alpine/v3.11/main/" > /etc/apk/repositories

COPY --from=builder /go/clash /usr/local/bin/
COPY --from=builder /go/Country.mmdb /root/.config/clash/
COPY config.yaml.example /root/.config/clash/config.yaml
COPY entrypoint.sh /usr/local/bin/
COPY scripts/setup-tun.sh /usr/lib/clash/setup-tun.sh

RUN set -eux; \
    \
    chmod a+x /usr/local/bin/clash /usr/local/bin/entrypoint.sh /usr/lib/clash/setup-tun.sh; \
    apk add --no-cache libcap; \
    # dumped by `pscap` of package `libcap-ng-utils`
    setcap cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,cap_net_raw,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap,cap_net_admin=+ep /usr/local/bin/clash; \
    runDeps=' \
        iptables \
        ip6tables \
        ipset \
        iproute2 \
        curl \
        bind-tools \
        # eudev \
    '; \
    apk add --no-cache \
        $runDeps \
        bash \
        bash-doc \
        bash-completion \
    ; \
    \
    rm -rf /var/cache/apk/*

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories

WORKDIR /clash_config

ENTRYPOINT ["entrypoint.sh"]
CMD ["su", "-s", "/bin/bash", "-c", "/usr/local/bin/clash -d /clash_config", "nobody"]
