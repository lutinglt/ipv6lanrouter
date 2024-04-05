FROM debian:12.5-slim

COPY ipv6lanrouter.sh /ipv6lanrouter.sh

RUN apt-get update &&\
    apt-get -y install --no-install-recommends --no-install-suggests iproute2 radvd ndppd jq &&\
    apt-get -y clean && rm -rf /var/lib/apt/lists/* &&\
    chmod +x /ipv6lanrouter.sh

CMD ["/ipv6lanrouter.sh"]
