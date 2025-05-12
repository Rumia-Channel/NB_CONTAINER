#!/bin/bash
set -e

# クローン
if [ "$AUTO_CLONE" = "true" ] && [ ! -d /app/code/.git ]; then
  git clone --depth=1 --branch "$GIT_BRANCH" "$GIT_REPO" /app/code
fi

# 設定ファイルの配置
echo "[app] 設定ファイルを配置します"

mkdir -p /app/code/setting
cp -f /app/files/setting.ini /app/code/setting/setting.ini

mkdir -p "$COOKIE_PATH"
cp -r /app/files/cookie/* "$COOKIE_PATH/"

mkdir -p /app/code/crawler
cp -r /app/files/crawler/* /app/code/crawler/

# 実行
cd /app/code
chmod +x ./main.sh
exec ./main.sh
