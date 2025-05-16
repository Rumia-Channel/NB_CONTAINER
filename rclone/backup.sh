#!/bin/sh
set -eu
# pipefail は BusyBox ash でも有効なので明示
set -o pipefail

error_trap() {
  echo "[ERROR] エラーが発生しました (行:${1:-})"
  exit 1
}
trap 'error_trap $LINENO' ERR

# =====================================
# 環境変数のデフォルト設定
# =====================================
: "${WEBDAV_URL:?WEBDAV_URL が未設定です}"   # 例: https://example.com/webdav
: "${WEBDAV_VENDOR:?WEBDAV_VENDOR が未設定です}" # nextcloud など
: "${WEBDAV_USER:?WEBDAV_USER が未設定です}"
: "${WEBDAV_PASS:?WEBDAV_PASS が未設定です}"
: "${WEBDAV_PATH:?WEBDAV_PATH が未設定です}"   # 例: /backup
WEBDAV_REMOTE_NAME=${WEBDAV_REMOTE_NAME:-mywebdav}

# =====================================
# rclone.conf 作成
# =====================================
ENC_PASS=$(rclone obscure "${WEBDAV_PASS}")
mkdir -p /config
cat <<EOF > /config/rclone.conf
[${WEBDAV_REMOTE_NAME}]
type   = webdav
url    = ${WEBDAV_URL}
vendor = ${WEBDAV_VENDOR}
user   = ${WEBDAV_USER}
pass   = ${ENC_PASS}
EOF

# =====================================
# パス定義
# =====================================
LOCAL="/share/data"
REMOTE="${WEBDAV_REMOTE_NAME}:${WEBDAV_PATH}"
BACKUP_ROOT_LOCAL="/share/_archive/data"                       # /share/data とは別ツリー
BACKUP_ROOT_REMOTE="${WEBDAV_REMOTE_NAME}:archive${WEBDAV_PATH}" # REMOTE と重ならないツリー
READY_FILE="${LOCAL}/.ready"

# =====================================
# 簡易復元 (jq 非依存版)
# =====================================
#   ・リモート側のバイト数がローカルより大きいときだけローカルへコピー
#   ・jq を使わず grep/cut だけで JSON を粗く抽出
# =====================================
get_bytes() {
  # $1: rclone size --json の結果文字列
  printf '%s' "$1" | grep -o '"bytes":[0-9]*' | cut -d: -f2
}

check_and_restore_if_needed() {
  sub="$1"

  # rclone size を JSON で取得し jq でバイト数を抽出
  remote_json=$(rclone size "${REMOTE}/${sub}" --config /config/rclone.conf --json 2>/dev/null || echo '{"bytes":0}')
  local_json=$(rclone size "${LOCAL}/${sub}"  --config /config/rclone.conf --json 2>/dev/null || echo '{"bytes":0}')

  remote_size=$(printf '%s
' "$remote_json" | jq '.bytes')
  local_size=$(printf '%s
' "$local_json"  | jq '.bytes')

  if [ "$remote_size" -gt "$local_size" ]; then
    echo "[restore] ${sub} をリモートから復元 (${local_size}→${remote_size} B)"
    rclone copy "${REMOTE}/${sub}" "${LOCAL}/${sub}" --config /config/rclone.conf --progress
  fi
}

# =====================================
# 初回同期 (WebDAV → ローカル)
# =====================================
initial_sync() {
  echo "[rclone] 初回セットアップ"
  rclone deletefile "${REMOTE}/.ready" --config /config/rclone.conf --ignore-errors || true
  rm -f "${READY_FILE}"

  echo "[rclone] 初回フルコピー (remote → local)"
  rclone sync "${REMOTE}" "${LOCAL}" --config /config/rclone.conf --progress --checksum

  echo "[rclone] 整合チェック"
  for path in "${LOCAL}"/*; do
    [ -d "$path" ] || continue
    check_and_restore_if_needed "${path##*/}"
  done

  touch "${READY_FILE}"
  echo "[rclone] 初回完了 (.ready 作成)"
}

# =====================================
# バックアップ世代整理 (BusyBox 対応)
#   ・find の -printf を使わずシンプルな for ループ
#   ・削除基準は "7 days ago" を busybox date -d で計算
# =====================================
prune_backups() {
  target_root="$1"   # パス or リモート
  is_remote="$2"     # "remote" | "local"

  NOW=$(date +%s)
  CUTOFF=$(( NOW - 7*24*3600 ))
  THRESHOLD=$(date -u -d "@${CUTOFF}" +%Y-%m-%d 2>/dev/null || date -u -r "${CUTOFF}" +%Y-%m-%d)
  echo "[prune] ${target_root}: ${THRESHOLD} より前の世代を削除"

  if [ "$is_remote" = "remote" ]; then
    # --- WebDAV 側: rclone コマンドで列挙＆削除 ---
    for sub in $(rclone lsd "${target_root}" --config /config/rclone.conf 2>/dev/null | awk '{print $5}'); do
      [ "$sub" \< "$THRESHOLD" ] || continue
      echo "  purge ${sub}"
      rclone purge "${target_root}/${sub}" --config /config/rclone.conf || true
    done
    rclone delete "${target_root}" --min-age 7d --config /config/rclone.conf --ignore-errors || true
    rclone rmdirs "${target_root}" --config /config/rclone.conf --ignore-errors || true
  else
    # --- ローカル側: BusyBox find だけで処理 ---
    [ -d "${target_root}" ] || return 0
    for dir in "${target_root}"/*; do
      [ -d "$dir" ] || continue
      name="${dir##*/}"
      [ "$name" \< "$THRESHOLD" ] || continue
      echo "  rm -rf ${name}"
      rm -rf "${dir}" || true
    done
    # 空ディレクトリ掃除
    find "${target_root}" -type d -empty -delete 2>/dev/null || true
  fi
}

# =====================================
# 定期 bisync
# =====================================
periodic_sync() {
  TODAY=$(date +%Y-%m-%d)
  echo "[rclone] bisync start (backup-dir1: ${BACKUP_ROOT_LOCAL}/${TODAY}, backup-dir2: ${BACKUP_ROOT_REMOTE}/${TODAY})"

  if [ ! -f "${LOCAL}/.bisync_initialized" ]; then
    BISYNC_OPT="--resync"
    echo "  --resync (初回 bisync)"
  else
    BISYNC_OPT=""
  fi

  rclone bisync "${LOCAL}" "${REMOTE}" \
    --config /config/rclone.conf \
    --backup-dir1 "${BACKUP_ROOT_LOCAL}/${TODAY}" \
    --backup-dir2 "${BACKUP_ROOT_REMOTE}/${TODAY}" \
    --checksum \
    ${BISYNC_OPT} \
    --verbose

  touch "${LOCAL}/.bisync_initialized"
  prune_backups "${BACKUP_ROOT_REMOTE}" "remote"
  prune_backups "${BACKUP_ROOT_LOCAL}" "local"
}

# =====================================
# メインループ
# =====================================
main() {
  mkdir -p "${LOCAL}" "${BACKUP_ROOT_LOCAL}"
  initial_sync
  while :; do
    periodic_sync
    echo "[rclone] 完了。60分後再実行"
    sleep 3600
  done
}

main "$@"