# ベースイメージに rclone/rclone を使う
FROM rclone/rclone:latest

# jq を追加でインストール
RUN apk add --no-cache jq

# 設定やスクリプトをコンテナにコピー
COPY backup.sh /backup.sh
COPY rclone.conf /config/rclone.conf

# エントリポイントを設定
ENTRYPOINT ["/bin/sh", "/backup.sh"]