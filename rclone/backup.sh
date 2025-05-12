#!/bin/sh
set -e

# === rclone.conf を環境変数から動的に生成 ===
cat <<EOF > /config/rclone.conf
[${WEBDAV_REMOTE_NAME}]
type = webdav
url = ${WEBDAV_URL}
vendor = ${WEBDAV_VENDOR}
user = ${WEBDAV_USER}
pass = ${WEBDAV_PASS_ENC}
EOF

LOCAL="/share/data"
# リモート先のルートフォルダ
REMOTE="${WEBDAV_REMOTE_NAME}:${WEBDAV_PATH}"
# 世代管理用アーカイブ（パス末尾に -archive を付与）
BACKUP_ROOT="${WEBDAV_REMOTE_NAME}:${WEBDAV_PATH}-archive"
READY_FILE="$LOCAL/.ready"

echo "[rclone] .ready を初期化します"
rm -f "$READY_FILE"

echo "[rclone] 初回 WebDAV → ローカル整合確認を行います..."

# フォルダごとの容量比較関数
check_and_restore_if_needed() {
  SUBPATH=$1
  LOCAL_PATH="$LOCAL/$SUBPATH"
  REMOTE_PATH="$REMOTE/$SUBPATH"

  mkdir -p "$LOCAL_PATH"

  LOCAL_SIZE=$(du -sb "$LOCAL_PATH" | awk '{print $1}')
  REMOTE_SIZE=$(rclone size "$REMOTE_PATH" --json --config /config/rclone.conf | jq .bytes || echo 0)

  echo "[$SUBPATH] Local: $LOCAL_SIZE / Remote: $REMOTE_SIZE"

  if [ "$REMOTE_SIZE" -gt "$LOCAL_SIZE" ]; then
    echo "[$SUBPATH] WebDAVの方が大きいため、復元を実施します"
    rclone sync "$REMOTE_PATH" "$LOCAL_PATH" --progress --config /config/rclone.conf
  else
    echo "[$SUBPATH] ローカルの方が新しいか一致、復元は不要です"
  fi
}

# 任意の対象サブフォルダを列挙
SUBDIRS=$(find "$LOCAL" -mindepth 1 -maxdepth 1 -type d | xargs -n1 basename 2>/dev/null || true)
for SUB in $SUBDIRS; do
  check_and_restore_if_needed "$SUB"
done

# .ready を作成して app/nginx に起動許可を出す
echo "[rclone] 初回整合完了、.ready を作成します"
touch "$READY_FILE"

# === 通常の定期バックアップループ ===
while true; do
  TODAY=$(date +"%Y-%m-%d")

  echo "[rclone] 差分バックアップ前に WebDAV → ローカルの差分を確認します..."

  for SUB in $(find "$LOCAL" -mindepth 1 -maxdepth 1 -type d | xargs -n1 basename 2>/dev/null || true); do
    check_and_restore_if_needed "$SUB"
  done

  echo "[rclone] 差分バックアップを開始します..."

  rclone copy "$LOCAL" "$REMOTE" \
    --min-age 5m \
    --update \
    --progress \
    --config /config/rclone.conf

  rclone move \
    --backup-dir="$BACKUP_ROOT/$TODAY" \
    "$LOCAL" "$REMOTE" \
    --min-age 5m \
    --config /config/rclone.conf

  echo "[rclone] 古い世代を削除します（7日以上前）"
  rclone delete \
    --min-age 7d "$BACKUP_ROOT" \
    --config /config/rclone.conf
  rclone rmdirs \
    --min-age 7d "$BACKUP_ROOT" \
    --config /config/rclone.conf

  echo "[rclone] バックアップ完了。60分待機..."
  sleep 3600
done