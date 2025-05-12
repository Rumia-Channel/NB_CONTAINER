FROM python:3.12-slim

# 必要なパッケージをインストール
RUN apt-get update && \
    apt-get install -y git bash && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 作業ディレクトリ
WORKDIR /app

# エントリポイントスクリプトのみをコピー（files は volume にするなら除外）
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# デフォルトコマンド
CMD ["/entrypoint.sh"]
