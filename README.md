# IPv6 LAN Router

![Version](https://img.shields.io/docker/v/lutinglt/ipv6lanrouter/latest?arch=amd64&sort=semver&color=066da5) ![Docker Pulls](https://img.shields.io/docker/pulls/lutinglt/ipv6lanrouter.svg?style=flat&label=pulls&logo=docker) ![Docker Size](https://img.shields.io/docker/image-size/lutinglt/ipv6lanrouter/latest?color=066da5&label=size) ![License](https://img.shields.io/github/license/lutinglt/ipv6lanrouter)

Assign IPv6 addresses to networks that can't get IPv6 addresses, redistribute IPv6 addresses on the LAN, and be transparent to higher-level routing.

## Features

- [x] Easy to deploy and out-of-the-box
- [x] [Docker Deploy](https://hub.docker.com/r/lutinglt/ipv6lanrouter)
- [x] Supports automatic multi-LAN assignment
- [x] Supports automatic recognition of WAN interfaces
- [x] Supports recognizing dynamic prefix of WAN port and modifying LAN prefix automatically.
- [x] Stateless only
- [x] No PD server required, inter-subnet routing
- [x] LAN interface IPv6 prefix matches IPv4 and MAC address assignment rules for Docker 26.0.0
- [x] Global IPv6 addresses can be assigned to containers under a Docker bridged network

## Getting Started

Via `docker-compose.yml`

```yaml
services:
  ipv6lanrouter:
    image: lutinglt/ipv6lanrouter:latest
    container_name: ipv6lanrouter
    hostname: ipv6lanrouter
    restart: on-failure
    networks:
#  macvlan is WAN(Interfaces capable of obtaining IPv6 global addresses)
      macvlan:
        ipv4_address: *.*.*.*
#  bridge is LAN(Interfaces that cannot obtain IPv6 global addresses)
      bridge1:
        ipv4_address: *.*.*.*
      bridge2:
        ipv4_address: *.*.*.*
      bridge3:
        ipv4_address: *.*.*.*
   environment:
      - TZ=Asia/Shanghai
      - CHECK=3
      - LAN_MODE=docker
      - PREFIXLEN=60
      - MTU=0
      - RDNSS=*:*:*:*;*:*:*:*;
      - EXCLUDE_SUB=00;01;02;03;...;
      - EXCLUDE_NUM1=0;1;2;3;...;
      - EXCLUDE_NUM2=0;1;2;3;...;
    cap_add:
      - NET_ADMIN
    sysctls:
      - "net.ipv6.conf.all.forwarding=1"
      - "net.ipv6.conf.all.proxy_ndp=1"
      - "net.ipv6.conf.all.accept_ra=2"
      - "net.ipv6.conf.default.forwarding=1"
      - "net.ipv6.conf.default.proxy_ndp=1"
      - "net.ipv6.conf.default.accept_ra=2"
```

## Configuration

| Variable  | Description                                                  | Default |
| --------- | ------------------------------------------------------------ | ------- |
| CHECK     | WAN port dynamic prefix detection interval (Unit: Seconds)   | 3       |
| LAN_MODE  | LAN network type                                             | docker  |
| PREFIXLEN | IPv6-assigned prefix length for higher-level routes (WAN)    | 60      |
| MTU       | MTU value for broadcasting when assigning IPv6 to LANs       | 0       |
| RDNSS     | Ditto, broadcast recursive DNS servers (Split each address with ";") |         |

### PREFIXLEN && LAN_MODE

- Only prefix lengths `56` `58` `60` `62` `64` are supported.

- If the `PREFIXLEN` is not `64`, the WAN port address will be excluded from the subnet address pool and then the LAN port address will be assigned.

- If the `PREFIXLEN` is `64`, the default LAN ports are all Docker bridge networks, and the IPv6 subnet address and prefix length are calculated based on the MAC address assigned to the IPv4 prefix length of the bridge network in Docker 26.0.0. (Linux stateless IPv6 addresses are calculated by default using EUI64).

> If the IPv6 address is not EUI64-generated, linux can use EUI64 to calculate the IPv6 address by setting the kernel parameter `net.ipv6.conf.all.addr_gen_mode=0` `net.ipv6.conf.default.addr_gen_mode=0`.

- If the `PREFIXLEN` is `64`, and `LAN_MODE` is set to `net` or any other value, only one LAN is supported and there is no communication between LAN port LAN and WAN port LAN.

| PREFIXLEN | WANIP (Example)          | Subnet Address Pool |
| --------- | ------------------------ | ------------------- |
| 56        | 2000:2000:2000:20xx::/64 | 00-ff               |
| 58        | 2000:2000:2000:20xx::/64 | 00-7f / 80-ff       |
| 60        | 2000:2000:2000:200x::/64 | 0-f                 |
| 62        | 2000:2000:2000:200x::/64 | 0-7 / 8-f           |

### EXCLUDE_SUB

Addresses to exclude when assigning subnets (Supports two digits or one digit in hexadecimal only) (Split each address with ";")

| PREFIXLEN | Value         |
| --------- | ------------- |
| 56        | 00-ff         |
| 58        | 00-7f / 80-ff |
| 60        | 0-f           |
| 62        | 0-7 / 8-f     |

### EXCLUDE_NUM1 && EXCLUDE_NUM2

Facilitates exclusion of unassigned prefixes (Supports one digit in hexadecimal only) (Split each address with ";")

> No conflict with EXCLUDE_SUB, can be repeated.

| EXCLUDE_NUM1 | EXCLUDE_NUM2 | Value (EXCLUDE_SUB)     |
| ------------ | ------------ | ----------------------- |
| 0            | 0;1;2;3      | 00;01;02;03             |
| 0;1          | 0;1;2;3      | 00;01;02;03;10;11;12;13 |

