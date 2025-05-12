#!/bin/bash
set -e

echo "[tailscale] 起動準備中..."

tailscaled &

# tailscaledが使えるようになるまで待機
TRIES=0
until tailscale status &>/dev/null || [ $TRIES -gt 10 ]; do
  sleep 1
  TRIES=$((TRIES+1))
done

echo "[tailscale] 接続開始: ${TS_HOSTNAME}.ts.net"
tailscale up --authkey="${TS_AUTHKEY}" --hostname="${TS_HOSTNAME}"

# TLS証明書がなければ取得
CERT_DIR="/var/lib/tailscale/certs"
if [ ! -f "$CERT_DIR/${TS_HOSTNAME}.ts.net.crt" ]; then
  echo "[tailscale] 証明書を取得中..."
  tailscale cert "${TS_HOSTNAME}.ts.net"
fi

# 証明書配置
cp "$CERT_DIR/${TS_HOSTNAME}.ts.net.crt" /etc/nginx/ssl/tls.crt
cp "$CERT_DIR/${TS_HOSTNAME}.ts.net.key" /etc/nginx/ssl/tls.key

echo "[nginx] 起動"
exec nginx -g 'daemon off;'
