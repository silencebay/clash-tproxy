# docker_global_transparent_proxy
使用clash +docker 进行路由转发实现全局透明代理

## 食用方法
1. 开启混杂模式

    `ip link set eth0 promisc on`

1. docker创建网络,注意将网段改为你自己的

    `docker network create -d macvlan --subnet=192.168.5.0/24 --gateway=192.168.5.1 -o parent=eth0 macnet`

1. 提前准备好正确的clash config

1. 运行容器

    `sudo docker run --name clash-tproxy -d -v /your/path/clash_config:/clash_config  --network macnet --ip 192.168.5.254 ghcr.io/silencebay/clash-tproxy:premium-latest`

    ```yaml
    version: '3.2'
    services:
      clash-tproxy:
        container_name: clash-tproxy
        image: ghcr.io/silencebay/clash-tproxy:premium-latest
        logging:
          options:
            max-size: '10m'
            max-file: '3'
        restart: unless-stopped
        #entrypoint: tail -f /dev/null
        #command: tail -f /dev/null
        volumes:
          - ./clash_config:/clash_config
        environment:
          - TZ=Asia/Shanghai
          - EN_MODE=redir-host
        cap_add:
          - NET_ADMIN
        networks:
          dMACvLAN:
            ipv4_address: 192.168.5.254
          aio:
        dns:
          - 114.114.114.114

    networks:
      dMACvLAN:
        external:
          name: macnet
    ```

1. 将手机/电脑等客户端 网关设置为容器ip,如192.168.5.254 ,dns也设置成这个


## 附注 : 

1. 只要规则设置的对, 支持国内直连,国外走代理
1. 只在linux 测试过,win没试过, mac是不行, 第二步创建网络不行, docker自己的问题, 说不定以后哪天docker for mac支持了?

## 构建方法
`docker buildx build --platform linux/386,linux/amd64,linux/arm/v7,linux/arm64/v8 -t <your_username>/clash-tproxy:premium-latest . --push`

## clash 配置参考

### TUN 模式

<details>
  <summary>docker-compose.yml</summary>

  ```yaml
  version: "3.4"

  services:
    clash-tproxy:
      container_name: clash-tproxy
      image: ghcr.io/silencebay/clash-tproxy:premium-latest
      logging:
        options:
          max-size: '10m'
          max-file: '3'
      restart: unless-stopped
      volumes:
        - ./clash_config:/clash_config
      environment:
        - TZ=Asia/Shanghai
        - EN_MODE=redir-host
        - EN_MODE_TUN=1
      cap_add:
        - NET_ADMIN
      networks:
        dMACvLAN:
          ipv4_address: 192.168.5.254
      dns:
        - 114.114.114.114

  networks:
    dMACvLan:
      external:
        name: macnet
  ```
</details>

<details>
  <summary>clash config.yaml</summary>

  ```yaml
  # Port of HTTP(S) proxy server on the local end
  # port: 7890

  # Port of SOCKS5 proxy server on the local end
  socks-port: 7891

  # Transparent proxy server port for Linux and macOS
  # redir-port: 7892

  # HTTP(S) and SOCKS5 server on the same port
  # mixed-port: 7890

  # authentication of local SOCKS5/HTTP(S) server
  # authentication:
  #  - "user1:pass1"
  #  - "user2:pass2"

  # Set to true to allow connections to the local-end server from
  # other LAN IP addresses
  allow-lan: true

  # This is only applicable when `allow-lan` is `true`
  # '*': bind all IP addresses
  # 192.168.122.11: bind a single IPv4 address
  # "[aaaa::a8aa:ff:fe09:57d8]": bind a single IPv6 address
  bind-address: "*"

  # Clash router working mode
  # rule: rule-based packet routing
  # global: all packets will be forwarded to a single endpoint
  # direct: directly forward the packets to the Internet
  mode: rule

  # Clash by default prints logs to STDOUT
  # info / warning / error / debug / silent
  log-level: debug

  # When set to false, resolver won't translate hostnames to IPv6 addresses
  ipv6: false

  # RESTful web API listening address
  external-controller: 0.0.0.0:9090

  # A relative path to the configuration directory or an absolute path to a
  # directory in which you put some static web resource. Clash core will then
  # serve it at `http://{{external-controller}}/ui`.
  # external-ui: dashboard

  # Secret for the RESTful API (optional)
  # Authenticate by spedifying HTTP header `Authorization: Bearer ${secret}`
  # ALWAYS set a secret if RESTful API is listening on 0.0.0.0
  # secret: ""

  # Outbound interface name
  # interface-name: en0

  # Static hosts for DNS server and connection establishment, only works
  # when `dns.enhanced-mode` is `redir-host`.
  #
  # Wildcard hostnames are supported (e.g. *.clash.dev, *.foo.*.example.com)
  # Non-wildcard domain names have a higher priority than wildcard domain names
  # e.g. foo.example.com > *.example.com > .example.com
  # P.S. +.foo.com equals to .foo.com and foo.com
  hosts:
    # '*.clash.dev': 127.0.0.1
    # '.dev': 127.0.0.1
    # 'alpha.clash.dev': '::1'

  tun:
    enable: true
    stack: system # or gvisor
    dns-hijack:
      - 192.168.5.252
    #   - 8.8.8.8:53
    #   - tcp://8.8.8.8:53
    # macOS-auto-route: true # auto set global route
    # macOS-auto-detect-interface: true # conflict with interface-name

  # DNS server settings
  # This section is optional. When not present, the DNS server will be disabled.
  dns:
    enable: true
    listen: 0.0.0.0:1053
    # ipv6: false # when the false, response to AAAA questions will be empty

    # These nameservers are used to resolve the DNS nameserver hostnames below.
    # Specify IP addresses only
    default-nameserver:
      - 192.168.5.252
      # - 114.114.114.114
      # - 8.8.8.8
    enhanced-mode: redir-host # or fake-ip
    fake-ip-range: 198.18.0.1/16 # Fake IP addresses pool CIDR
    # use-hosts: true # lookup hosts and return IP record

    # Hostnames in this list will not be resolved with fake IPs
    # i.e. questions to these domain names will always be answered with their
    # real IP addresses
    # fake-ip-filter:
    #   - '*.lan'
    #   - localhost.ptlogin2.qq.com

    # Supports UDP, TCP, DoT, DoH. You can specify the port to connect to.
    # All DNS questions are sent directly to the nameserver, without proxies
    # involved. Clash answers the DNS question with the first result gathered.
    nameserver:
      - 192.168.5.252
      # - 114.114.114.114 # default value
      # - 8.8.8.8 # default value
      # - tls://dns.rubyfish.cn:853 # DNS over TLS
      # - https://1.1.1.1/dns-query # DNS over HTTPS

    # When `fallback` is present, the DNS server will send concurrent requests
    # to the servers in this section along with servers in `nameservers`.
    # The answers from fallback servers are used when the GEOIP country
    # is not `CN`.
    # fallback:
    #   - tcp://1.1.1.1

    # If IP addresses resolved with servers in `nameservers` are in the specified
    # subnets below, they are considered invalid and results from `fallback`
    # servers are used instead.
    #
    # IP address resolved with servers in `nameserver` is used when
    # `fallback-filter.geoip` is true and when GEOIP of the IP address is `CN`.
    #
    # If `fallback-filter.geoip` is false, results from `nameserver` nameservers
    # are always used if not match `fallback-filter.ipcidr`.
    #
    # This is a countermeasure against DNS pollution attacks.
    fallback-filter:
      geoip: true
      ipcidr:
        # - 240.0.0.0/4
      # domain:
      #   - '+.google.com'
      #   - '+.facebook.com'
      #   - '+.youtube.com'

  proxies:

...
```
</details>

### TProxy 模式

<details>
  <summary>docker-compose.yml</summary>

  ```yaml
  version: "3.4"

  services:
    clash-tproxy:
      container_name: clash-tproxy
      image: ghcr.io/silencebay/clash-tproxy:premium-latest
      logging:
        options:
          max-size: '10m'
          max-file: '3'
      restart: unless-stopped
      volumes:
        - ./clash_config:/clash_config
      environment:
        - TZ=Asia/Shanghai
        - EN_MODE=redir-host
      cap_add:
        - NET_ADMIN
      networks:
        dMACvLAN:
          ipv4_address: 192.168.5.254
      dns:
        - 114.114.114.114

  networks:
    dMACvLan:
      external:
        name: macnet
  ```
</details>

<details>
  <summary>clash config.yaml</summary>

  ```yaml
  # Port of HTTP(S) proxy server on the local end
  # port: 7890

  # Port of SOCKS5 proxy server on the local end
  socks-port: 7891

  # Transparent proxy server port for Linux and macOS
  # redir-port: 7892

  # Transparent proxy server port for Linux (TProxy TCP and TProxy UDP)
  tproxy-port: 7893

  # HTTP(S) and SOCKS5 server on the same port
  # mixed-port: 7890

  # authentication of local SOCKS5/HTTP(S) server
  # authentication:
  #  - "user1:pass1"
  #  - "user2:pass2"

  # Set to true to allow connections to the local-end server from
  # other LAN IP addresses
  allow-lan: true

  # This is only applicable when `allow-lan` is `true`
  # '*': bind all IP addresses
  # 192.168.122.11: bind a single IPv4 address
  # "[aaaa::a8aa:ff:fe09:57d8]": bind a single IPv6 address
  bind-address: "*"

  # Clash router working mode
  # rule: rule-based packet routing
  # global: all packets will be forwarded to a single endpoint
  # direct: directly forward the packets to the Internet
  mode: rule

  # Clash by default prints logs to STDOUT
  # info / warning / error / debug / silent
  log-level: debug

  # When set to false, resolver won't translate hostnames to IPv6 addresses
  ipv6: false

  # RESTful web API listening address
  external-controller: 0.0.0.0:9090

  # A relative path to the configuration directory or an absolute path to a
  # directory in which you put some static web resource. Clash core will then
  # serve it at `http://{{external-controller}}/ui`.
  # external-ui: dashboard

  # Secret for the RESTful API (optional)
  # Authenticate by spedifying HTTP header `Authorization: Bearer ${secret}`
  # ALWAYS set a secret if RESTful API is listening on 0.0.0.0
  # secret: ""

  # Outbound interface name
  # interface-name: en0

  # Static hosts for DNS server and connection establishment, only works
  # when `dns.enhanced-mode` is `redir-host`.
  #
  # Wildcard hostnames are supported (e.g. *.clash.dev, *.foo.*.example.com)
  # Non-wildcard domain names have a higher priority than wildcard domain names
  # e.g. foo.example.com > *.example.com > .example.com
  # P.S. +.foo.com equals to .foo.com and foo.com
  hosts:
    # '*.clash.dev': 127.0.0.1
    # '.dev': 127.0.0.1
    # 'alpha.clash.dev': '::1'

  # DNS server settings
  # This section is optional. When not present, the DNS server will be disabled.
  dns:
    enable: true
    listen: 0.0.0.0:53
    # ipv6: false # when the false, response to AAAA questions will be empty

    # These nameservers are used to resolve the DNS nameserver hostnames below.
    # Specify IP addresses only
    default-nameserver:
      - 192.168.5.252
      # - 114.114.114.114
      # - 8.8.8.8
    enhanced-mode: redir-host # or fake-ip
    fake-ip-range: 198.18.0.1/16 # Fake IP addresses pool CIDR
    # use-hosts: true # lookup hosts and return IP record

    # Hostnames in this list will not be resolved with fake IPs
    # i.e. questions to these domain names will always be answered with their
    # real IP addresses
    # fake-ip-filter:
    #   - '*.lan'
    #   - localhost.ptlogin2.qq.com

    # Supports UDP, TCP, DoT, DoH. You can specify the port to connect to.
    # All DNS questions are sent directly to the nameserver, without proxies
    # involved. Clash answers the DNS question with the first result gathered.
    nameserver:
      - 192.168.5.252
      # - 114.114.114.114 # default value
      # - 8.8.8.8 # default value
      # - tls://dns.rubyfish.cn:853 # DNS over TLS
      # - https://1.1.1.1/dns-query # DNS over HTTPS

    # When `fallback` is present, the DNS server will send concurrent requests
    # to the servers in this section along with servers in `nameservers`.
    # The answers from fallback servers are used when the GEOIP country
    # is not `CN`.
    # fallback:
    #   - tcp://1.1.1.1

    # If IP addresses resolved with servers in `nameservers` are in the specified
    # subnets below, they are considered invalid and results from `fallback`
    # servers are used instead.
    #
    # IP address resolved with servers in `nameserver` is used when
    # `fallback-filter.geoip` is true and when GEOIP of the IP address is `CN`.
    #
    # If `fallback-filter.geoip` is false, results from `nameserver` nameservers
    # are always used if not match `fallback-filter.ipcidr`.
    #
    # This is a countermeasure against DNS pollution attacks.
    fallback-filter:
      geoip: true
      ipcidr:
        # - 240.0.0.0/4
      # domain:
      #   - '+.google.com'
      #   - '+.facebook.com'
      #   - '+.youtube.com'

  proxies:

...
```
</details>

## 设置客户端
设置客户端（或设置路由器DHCP）默认网关及DNS服务器为容器IP:192.168.5.254

以openwrt为例，在`/etc/config/dhcp`中`config dhcp 'lan'`段加入：

```
  list dhcp_option '6,192.168.5.254'
  list dhcp_option '3,192.168.5.254'
```
## 关于IPv6 DNS
使用过程中发现，若启用了IPv6，某些客户端(Android)会自动将DNS服务器地址指向默认网关(路由器)的ipv6地址，导致客户端不走docker中的dns服务器。

解决方案是修改路由器中ipv6的`通告dns服务器`为容器ipv6地址。

以openwrt为例，在`/etc/config/dhcp`中`config dhcp 'lan'`段加入：
```
  list dns 'fe80::fe80'
```

## 关于宿主机出口
由于docker网络采用`macvlan`的`bridge`模式，宿主机虽然与容器在同一网段，但是相互之间是无法通信的，所以无法通过`tproxy-gateway`透明代理。

### 解决方案1

让宿主机直接走主路由，不经过代理网关：

```bash
ip route add default via 192.168.5.254 dev eth0 # 设置静态路由
echo "nameserver 192.168.5.254" > /etc/resolv.conf # 设置静态dns服务器
```

### 解决方案2

利用多个macvlan接口之间是互通的原理，新建一个macvlan虚拟接口：

* 临时配置网络（重启后失效）

   ```bash
   ip link add link eth0 mac0 type macvlan mode bridge # 在eth0接口下添加一个macvlan虚拟接口
   ip addr add 192.168.5.250/24 brd + dev mac0 # 为mac0 分配ip地址
   ip link set mac0 up
   ip route del default #删除默认路由
   ip route add default via 192.168.5.254 dev mac0 # 设置静态路由
   echo "nameserver 192.168.5.254" > /etc/resolv.conf # 设置静态dns服务器
   ```

* 永久配置网络（重启也能生效）

   * 使用 nmcli (推荐）

      `nmcli connection add type macvlan dev eth0 mode bridge ifname mac30 ipv4.route-metric 10 ipv6.route-metric 10 autoconnect yes save yes`

      如果想自定义 ip 及网关，可执行：

      `nmcli connection add type macvlan dev eth0 mode bridge ifname mac30 ipv4.route-metric 10 ipv6.route-metric 10 ipv4.method manual ip4 192.168.5.250/24 gw4 192.168.5.254 autoconnect yes save yes`

      注意：需使用更低的 `metric` 来提高 `default` 路由的优先级

   * 宿主机（Debian）修改网络配置：`vi /etc/network/interface`

      以下配置不支持网线热插拔，热插拔后需手动重启网络。可借用 `ifplugd` 解决（操作不详）

      将：
   
      ```
      auto eth0
      iface eth0 inet static
      address 192.168.5.250
      broadcast 192.168.5.255
      netmask 255.255.255.0
      gateway 192.168.5.254
      dns-nameservers 192.168.5.254
      ```
   
      修改为：
   
      ```
      auto eth0
      iface eth0 inet manual
   
      auto macvlan
      iface macvlan inet static
      metric 10
      address 192.168.5.250
      netmask 255.255.255.0
      gateway 192.168.5.254
      dns-nameservers 192.168.5.254
      	pre-up ip link add $IFACE link eth0 type macvlan mode bridge
      	post-down ip link del $IFACE link eth0 type macvlan mode bridge
      ```
   
      或
   
      ```
      auto eth0
      iface eth0 inet manual
   
      auto macvlan
      iface macvlan inet manual
      	#pre-up ip monitor link dev eth0 | grep -q 'state UP'
      	pre-up while ! ip link show eth0 | grep -q 'state UP'; do echo "waiting for eth0 is ready"; sleep 2; done
      	pre-up while ! ip route show | grep -q '^default'; do echo "waiting eth0 got required rules"; sleep 2; done
      	pre-up while ! ip route show | grep -q '192.168.5.0/24 dev eth0'; do echo "waiting eth0 got required rules"; sleep 2; done
      	pre-up ip link add $IFACE link eth0 type macvlan mode bridge
      	pre-up ip addr add 192.168.5.250/24 brd + dev $IFACE
      	up ip link set $IFACE up
      	#up udevadm trigger
      	post-up ip route del default
      	post-up ip route del 192.168.5.0/24 dev eth0
      	post-up ip route add default via 192.168.5.254 dev $IFACE
      	post-down ip link del dev $IFACE
      	down ifdown eth0
      	down ifup eth0
      ```
   
      修改完后重启网络  `systemctl restart networking` 或者重启系统查看效果。


**参考资料**

[docker_global_transparent_proxy](https://github.com/YouYII/docker_global_transparent_proxy)

配置文件

[https://lancellc.gitbook.io/clash/whats-new/clash-tun-mode/clash-tun-mode-2/setup-for-redir-host-mode](https://lancellc.gitbook.io/clash/whats-new/clash-tun-mode/clash-tun-mode-2/setup-for-redir-host-mode)

路由及防火墙设置

[kr328-clash-setup-scripts](https://github.com/h0cheung/kr328-clash-setup-scripts)

overturn DNS

[overturn + clash in docker as dns server and transparent proxy gateway](https://gist.github.com/killbus/69fdabdd1d8ae8f4030f4f96307ffa1b)

宿主机配置

https://github.com/fanyh123/tproxy-gateway