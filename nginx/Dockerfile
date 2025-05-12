FROM nginx:stable

RUN apt-get update && \
    apt-get install -y curl iptables openssl tailscale && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]