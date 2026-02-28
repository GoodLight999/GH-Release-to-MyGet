# UniGetUI Auto Updater Repository

このリポジトリは、GitHub Releasesで公開されているソフトウェアの最新版を自動取得し、Chocolateyパッケージ（`.nupkg`）としてMyGetへプッシュするための仕組みです。

## 使い方（初期設定）

あなたが行う必要があるのは以下の手順です。

### 1. MyGetのAPIキー取得と登録
1. 今回作成したフィード `goodlight-desktop-repo` の画面に行きます。
2. `Feed Settings` > `Access Tokens (API Keys)` から新しいAPIキーを生成し、コピーします。
3. GitHub上のこのリポジトリのページに行き、`Settings` > `Secrets and variables` > `Actions` を開きます。
4. `New repository secret` をクリックし、名前に `MYGET_API_KEY`、値にコピーしたAPIキーを貼り付けて保存します。

### 2. 対象ソフトウェアのURLリストの登録（Variables）
パッケージを手動で作成する必要はありません。GitHubの変数を設定するだけで全自動で生成されます。

1. GitHubリポジトリの `Settings` > `Secrets and variables` > `Actions` を開きます。
2. 今度は **Variables** タブを選択し、`New repository variable` をクリックします。
3. 名前に `TARGET_URLS` と入力します。
4. 値（Value）に、自動更新したいソフトウェアのGitHub URLを改行区切りで入力して保存します。
   ```text
   https://github.com/jlcodes99/cockpit-tools
   https://github.com/koala73/worldmonitor
   ```

### 3. アクションの実行
1. GitHubの `Actions` タブから `Auto Update Packages` ワークフローを手動実行（`Run workflow`）して、正しくMyGetにパッケージがプッシュされるか確認します。
2. これ以降は毎日自動的にチェックが行われます。

### 4. クライアントPC (UniGetUI) 側の設定
管理者権限のPowerShellで以下を実行し、MyGetフィードをローカルのソースに追加します。
```powershell
choco source add -n="MyGetCustomFeed" -s="https://www.myget.org/F/goodlight-desktop-repo/api/v2"
```
これでUniGetUIから自動的に読み込まれるようになります。
