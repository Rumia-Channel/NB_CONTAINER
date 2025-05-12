# NB_CONTAINER

> Docker Compose テンプレート  
> Tailscale＋nginx（HTTPS 終端）＋アプリ（Git→`main.sh`実行）＋rcloneバックアップ  

---

## 注意!!
files/setting.ini の domain= = の値と .env の TS_HOSTNAM = の値は必ず一致させること。

---
## 📁 ディレクトリ構成

```text
project-root/
├── .env.example           # 環境変数テンプレート
├── docker-compose.yml     # Compose 定義
│
├── nginx/
│   ├── Dockerfile
│   ├── entrypoint.sh      # tailscaled→cert→nginx
│   └── conf.d/
│       └── default.conf   # HTTPS＋/api プロキシ設定
│
├── app/
│   ├── Dockerfile
│   └── entrypoint.sh      # Git clone→files配置→main.sh 実行
│
├── files/                 # テンプレート設定ファイル
│   ├── setting.ini
│   ├── cookie/…
│   └── crawler/…
│
└── rclone/
    ├── Dockerfile         # rclone＋jq
    ├── backup.sh          # 初回復元＋定期バックアップ
    └── rclone.conf        # （自動生成 or マウント）
````

---

## ⚙️ 前提・事前準備

1. **Docker ＆ Docker Compose** をインストール
2. リポジトリをクローン
3. 環境変数ファイルを作成 & 編集

   ```bash
   cp .env.example .env
   # その後 .env を開いて各種値を設定
   ```
4. `.env` は `.gitignore` に含め、機密情報をコミットしないこと

---

## 📝 `.env.example`（例）

```dotenv
# Tailscale
TS_ADMIN_KEY=tskey-api-xxxxxxxxxxxxxxxxxxxx
TAILNET_NAME=tail0exam.ts.net
TS_AUTHKEY=tskey-xxxxxxxxxxxxxxxxxxxx
TS_HOSTNAME=example.tail0exam.ts.net

# アプリ（Git）
GIT_REPO=https://github.com/your/repo.git
GIT_BRANCH=main

# WebDAV (rclone)
WEBDAV_URL=https://example.com/remote.php/webdav/
WEBDAV_USER=your-username
WEBDAV_PASS_ENC=encrypted:xxxxxxx
WEBDAV_VENDOR=nextcloud

# Cookie 保存先
COOKIE_PATH=/app/code/cookie
```

---

## 🚀 起動・停止

```bash
# ビルド＆起動
docker-compose up -d --build

# ログ確認
docker-compose logs -f nginx app rclone-backup

# 停止＆クリーン
docker-compose down
```

* **nginx**：Tailscale で HTTPS を受け、`/api/` を app へプロキシ
* **app**：Git クローン → `files/` から設定配置 → `main.sh` 実行
* **rclone-backup**：初回に WebDAV→ローカル復元→`.ready` ファイル作成、
  以降 1h ごとに差分バックアップ＆世代管理

---

## 🔒 セキュリティ・注意点

* `.ready` はドットファイルとして配置され、nginx 設定で公開を禁止
* WebDAV 側に追加されたファイルは定期的にローカルへ復元
* 機密情報は `.env` のみで管理し、リポジトリには含めない

---

## ⚙️ Kubernetes への移行ヒント

* `rclone-backup` を **initContainer** に置き換えると、Pod 起動前に必ず整合完了
* `emptyDir` や **PVC** で `/share/data` を共有
* nginx は **Ingress + cert-manager** で同等の HTTPS 終端に

---

## 🛠️ カスタマイズ例

* **バックアップ間隔** を変える → `backup.sh` の `sleep` 値を調整
* **世代保持日数** を変更 → `rclone delete --min-age` の値を変更
* **追加のボリューム** → `docker-compose.yml` に追記

---

## License

This project is licensed under the BSD 2-Clause License License.