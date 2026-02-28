# UniGetUI Auto Updater Repository

このリポジトリは、GitHub Releasesで公開されているソフトウェアの最新版を自動取得し、Chocolateyパッケージ（`.nupkg`）としてMyGetへプッシュするための仕組みです。

## 使い方（初期設定）

あなたが行う必要があるのは以下の手順です。

### 1. GitHubリポジトリへのプッシュ
1. このローカルフォルダ (`C:\Users\nakan\Desktop\Workspace\UniGetUI-AutoUpdater`) をあなたのGitHubの新しいパブリック/プライベートリポジトリとしてプッシュしてください。

### 2. MyGetのAPIキー取得と登録
1. 今回作成したフィード `goodlight-desktop-repo` の画面に行きます。
2. `Feed Settings` > `Access Tokens (API Keys)` から新しいAPIキーを生成し、コピーします。
3. GitHub上のこのリポジトリのページに行き、`Settings` > `Secrets and variables` > `Actions` を開きます。
4. `New repository secret` をクリックし、名前に `MYGET_API_KEY`、値にコピーしたAPIキーを貼り付けて保存します。

### 3. 対象ソフトウェアの追加・編集
サンプルの `my-awesome-app` フォルダをコピーして、自動更新したいソフトウェアごとにフォルダを作成します。

**変更が必要なファイル:**
- `*.nuspec`: `<id>`, `<version>`, `<title>` などを対象ソフトに合わせて書き換えます。
- `update.ps1`: `$github_owner` と `$github_repo` を対象のGitHubリポジトリ名に変更します。場合によってはダウンロードURLを取得するための正規表現（`$asset`の抽出部分）の調整が必要です。
- `tools/chocolateyInstall.ps1`: サイレントインストールの引数（`$silentArgs`）をインストーラの種類（例えばNSISなら`/S`、InnoSetupなら`/VERYSILENT`など）に合わせて変更します。

### 4. アクションの実行
1. GitHubの `Actions` タブから `Auto Update Packages` ワークフローを手動実行（`Run workflow`）して、正しくMyGetにパッケージがプッシュされるか確認します。
2. これ以降は毎日自動的にチェックが行われます。

### 5. クライアントPC (UniGetUI) 側の設定
管理者権限のPowerShellで以下を実行し、MyGetフィードをローカルのソースに追加します。
```powershell
choco source add -n="MyGetCustomFeed" -s="https://www.myget.org/F/goodlight-desktop-repo/api/v2"
```
これでUniGetUIから自動的に読み込まれるようになります。
