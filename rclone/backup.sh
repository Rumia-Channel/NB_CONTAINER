#!/bin/sh
set -e

# === 環境変数のデフォルト設定 ===
WEBDAV_REMOTE_NAME=${WEBDAV_REMOTE_NAME:-mywebdav}

# パスワードを rclone obscure で隠蔽
ENC_PASS=$(rclone obscure "${WEBDAV_PASS}")

# rclone.conf を動的に生成
cat <<EOF > /config/rclone.conf
[${WEBDAV_REMOTE_NAME}]
type = webdav
url = ${WEBDAV_URL}
vendor = ${WEBDAV_VENDOR}
user = ${WEBDAV_USER}
pass = ${ENC_PASS}
EOF

LOCAL="/share/data"
REMOTE="${WEBDAV_REMOTE_NAME}:${WEBDAV_PATH}"
BACKUP_ROOT="${WEBDAV_REMOTE_NAME}:${WEBDAV_PATH}-archive"
READY_FILE="$LOCAL/.ready"

echo "[rclone] .ready を初期化します"
rm -f "$READY_FILE"

echo "[rclone] 初回起動：LOCAL配下をクリア（nginxデフォルト等）"
find "$LOCAL" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

# フォルダごとの容量比較＆復元関数
echo "[rclone] 初回全体同期を行います…"
# 初回はルートごと sync して確実に全ファイルを取得
rclone sync "$REMOTE" "$LOCAL" \
  --config /config/rclone.conf \
  --progress

# 初回は LOCAL/* を glob でループ
for path in "$LOCAL"/*; do
  [ -d "$path" ] || continue
  SUB=${path##*/}
  check_and_restore_if_needed "$SUB"
done

echo "[rclone] 初回整合完了 → .ready 作成"
touch "$READY_FILE"

# === 定期バックアップループ ===
while true; do
  TODAY=$(date +"%Y-%m-%d")

  echo "[rclone] 定期同期前整合チェック…"
  for path in "$LOCAL"/*; do
    [ -d "$path" ] || continue
    SUB=${path##*/}
    check_and_restore_if_needed "$SUB"
  done

  echo "[rclone] ローカル→WebDAV 差分コピー開始…"
  rclone copy "$LOCAL" "$REMOTE" \
    --config /config/rclone.conf \
    --update --min-age 5m --progress

  echo "[rclone] 差分を世代バックアップに退避…"
  rclone mkdir "${BACKUP_ROOT}" --config /config/rclone.conf || true
  rclone move \
    --backup-dir="${BACKUP_ROOT}/${TODAY}" \
    "$LOCAL" "$REMOTE" \
    --config /config/rclone.conf --min-age 5m

  echo "[rclone] 古い世代を削除（7日以上前）…"
  rclone delete --min-age 7d "$BACKUP_ROOT" \
    --config /config/rclone.conf --ignore-errors
  rclone rmdirs --min-age 7d "$BACKUP_ROOT" \
    --config /config/rclone.conf --ignore-errors

  echo "[rclone] 完了。60分後再実行…"
  sleep 3600
done
