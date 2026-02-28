<div align="center">
  <h1>GH-Release-to-MyGet</h1>
  <p><b>Your Personal Automated Windows Package Manager</b></p>
  <a href="#japanese-日本語">日本語の説明はこちら</a>
</div>

## Overview (English)
This repository provides a fully automated pipeline that fetches the latest versions of Windows applications from any GitHub Releases and deploys them as **Chocolatey packages (.nupkg)** to a custom MyGet feed. 
By integrating this feed with **UniGetUI**, you can seamlessly install and update any obscure GitHub app with a single click.

### Features
* **AI-like 10-Tier Scoring Algorithm:** Automatically evaluates and picks the best asset (`.msixbundle`, `.appx`, `x64-setup.exe` over `arm64`, `i386`, or CLI tools).
* **Native 7z/ZIP Portable App Support:** If the app is distributed as a portable `.zip` or `.7z`, the pipeline natively extracts it, finds the core GUI executable, ignores CLI shims, and creates a clean Start Menu shortcut.
* **Smart Installer Detection:** Detects if an extracted portable archive is secretly just a wrapper for `setup.exe` and dynamically executes a silent installation instead of a portable drop.
* **Blazing Fast native API Hashing:** Bypasses downloading heavy multi-GB assets locally by extracting the native `digest` field provided directly by the GitHub Releases API.
* **"Set It & Forget It":** You only need to add the target GitHub URL to the GitHub Actions variables. The system runs every 3 hours and uses a transparent keepalive action to bypass GitHub's 60-day cron deactivation policy.

### Setup Guide
1. **Create a MyGet Feed**
   - Create a free account on MyGet and a new feed.
   - Go to `Feed Settings` > `Access Tokens (API Keys)` and generate a new Full Access API Key.
2. **Configure GitHub Secrets & Variables**
   - Fork or clone this repository to your GitHub account.
   - Go to `Settings` > `Secrets and variables` > `Actions`.
   - Add a repository **Secret** named `MYGET_API_KEY` and paste your API key.
   - Add a repository **Variable** named `TARGET_URLS` and paste the URLs of the GitHub repositories you want to track (one per line).
3. **Connect to UniGetUI (Client PC)**
   - Run the following in an elevated PowerShell to register your feed:
   ```powershell
   choco source add -n="MyGetCustomFeed" -s="https://www.myget.org/F/YOUR-FEED-NAME/api/v2"
   ```

---

<hr>

<h2 id="japanese-日本語">Overview (日本語)</h2>

このリポジトリは、GitHub Releasesで公開されているさまざまな形式（`exe`, `msi`, `zip`, `7z`, `msix` 等）のWindowsアプリケーションの最新版を自動監視・取得し、**完全自動で「Chocolateyパッケージ（.nupkg）」としてMyGetへプッシュ**するための最強の自動化基盤です。
これを **UniGetUI** のカスタムソースに登録することで、どんなマイナーなGitHubアプリでもワンクリックで管理・アップデートできるようになります。

### 主な機能と特級防御策
* **10段階の「ポイント制」AIスコアリング:** 無数のアセットの中から「あなたが一番求めているファイル」を1位に選び出します（ARM版への極大ペナルティ、MSIX形式への特大ボーナスなど）。
* **APIネイティブハッシュのハック:** Chocolateyが要求するSHA256ハッシュ確認のために数GBのファイルを毎回ダウンロードする無駄を防ぐため、GitHub APIの `digest` 値を直接抜き取ります。
* **強力な .7z / .zip ポータブル版対応:** 開発者が圧縮ファイルでポータブル版を配っていても、完全に解凍して中から「メインのGUIアプリ」を探し当て、不要なCLIツールを無視してWindowsのスタートメニューにショートカットを生成します。
* **「ZIPに偽装したインストーラー」のランタイム処刑:** 解凍した中身が単なる `setup.exe` だった場合、実行時にスクリプトが自己判断してポータブル配置から「サイレントバックグラウンドインストール」へ動的に切り替えます。
* **完全な不老不死（Keepalive）:** GitHub Actionsが3時間に1回巡回します。また、60日間コミットがないとActionsが止まる仕様に対して、自動でダミーコミットを打って回避します。

### 使い方（初期設定）

**1. MyGetのAPIキー取得と登録**
1. 作成したMyGetフィードの画面に行きます。
2. `Feed Settings` > `Access Tokens (API Keys)` から新しいAPIキーを生成し、コピーします。
3. GitHub上のこのリポジトリのページに行き、`Settings` > `Secrets and variables` > `Actions` を開きます。
4. `New repository secret` をクリックし、名前に `MYGET_API_KEY`、値にコピーしたAPIキーを貼り付けて保存します。

**2. 対象ソフトウェアのURLリストの登録（Variables）**
1. 同じく `Settings` > `Secrets and variables` > `Actions` を開きます。
2. **Variables** タブを選択し、`New repository variable` をクリックします。
3. 名前に `TARGET_URLS` と入力し、値（Value）に更新したいソフトウェアのGitHub URLを改行区切りで入力します。
   ```text
   https://github.com/jlcodes99/cockpit-tools
   https://github.com/koala73/worldmonitor
   ```

**3. クライアントPC (UniGetUI) 側の設定**
管理者権限のPowerShellで以下を実行し、MyGetフィードをローカルのソースに追加します。
```powershell
choco source add -n="MyGetCustomFeed" -s="https://www.myget.org/F/goodlight-desktop-repo/api/v2"
```
これでUniGetUIから自動的に読み込まれるようになります！
