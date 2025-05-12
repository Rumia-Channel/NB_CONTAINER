#!/bin/bash
set -euo pipefail

# --- ① 必須変数チェック ---
: "${TS_ADMIN_KEY:?TS_ADMIN_KEY が未設定です}"
: "${TAILNET_NAME:?TAILNET_NAME が未設定です}"
: "${TS_HOSTNAME:?TS_HOSTNAME が未設定です}"
: "${TS_AUTHKEY:?TS_AUTHKEY が未設定です}"

NODE="${TS_HOSTNAME%%.*}"   # narou-test
FQDN="${TS_HOSTNAME}"       # narou-test.taila0dfa.ts.net

# --- 既存 narou-test デバイスを全削除 ---
echo "[tailscale] FQDN に一致する既存デバイスを削除: ${FQDN}"
# ① デバイス一覧取得
devices_json=$(
  curl -s -u "${TS_ADMIN_KEY}:" \
    "https://api.tailscale.com/api/v2/tailnet/${TAILNET_NAME}/devices"
)

# ② .name フィールドが完全一致するデバイスID を抽出
device_id=$(echo "$devices_json" | jq -r \
  '.devices[] | select(.name == "'"${FQDN}"'") | .id')

if [ -n "$device_id" ] && [ "$device_id" != "null" ]; then
  echo "[tailscale] 削除対象 ID=${device_id}"
  # ③ 正しいエンドポイントで削除
  curl -s -u "${TS_ADMIN_KEY}:" -X DELETE \
    "https://api.tailscale.com/api/v2/device/${device_id}"
  echo "[tailscale] 削除完了: ${FQDN} (${device_id})"
else
  echo "[tailscale] 削除対象が見つかりません: ${FQDN}"
fi

# --- ③ tailscaled 起動／wait ---
echo "[tailscale] 起動準備中…"
tailscaled &
TRIES=0
until tailscale status &>/dev/null || [ $TRIES -gt 10 ]; do
  sleep 1; TRIES=$((TRIES+1))
done

# --- ④ 新規 narou-test で up & cert ---
echo "[tailscale] 接続: ${NODE}"
tailscale up --authkey="${TS_AUTHKEY}" --hostname="${NODE}"

echo "[tailscale] 証明書取得: ${FQDN}"
tailscale cert "${FQDN}" || echo "[warning] cert 取得失敗"

# --- ⑤ 証明書を nginx 用ディレクトリへ ---
CERT_DIR="/var/lib/tailscale/certs"
cp "${CERT_DIR}/${FQDN}.crt" /etc/nginx/ssl/tls.crt
cp "${CERT_DIR}/${FQDN}.key" /etc/nginx/ssl/tls.key

# --- ⑥ nginx 起動 ---
echo "[nginx] 起動"
exec nginx -g 'daemon off;'