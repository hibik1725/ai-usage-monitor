# SETUP.md — QuotaBar セットアップ手順（AI エージェント向け）

このファイルは **Claude Code / Codex CLI / Cursor Agent** などに渡し、ユーザー代わりにセットアップを完了させるための手順書です。
人間が読んでもそのまま実行できます。

リポジトリ: https://github.com/hibik1725/ai-usage-monitor

---

## 人間向け: AI に渡すプロンプト

以下をコピーして、利用中の AI コーディングエージェントに貼り付けてください。

```text
このリポジトリを macOS にセットアップしてください。

1. git clone git@github.com:hibik1725/ai-usage-monitor.git（未クローンなら）
2. リポジトリ直下の SETUP.md を読み、手順をすべて実行する
3. ./Scripts/setup.sh を実行してビルド・インストール・ログイン時自動起動・デスクトップ表示を有効化する
4. 検証コマンドを実行し、成功基準を満たすまで報告する
5. 失敗したら SETUP.md のトラブルシューティングに従い自己修復する

前提: macOS 14+、Xcode Command Line Tools 済み。
Codex / Claude Code / Grok のいずれか CLI でログイン済みであること。
```

---

## AI エージェント向け: 実行契約

あなた（AI エージェント）は次を **必ず** 守ってください。

1. **対話で止まらない** — 確認プロンプトが出るコマンドは非対話フラグを使う（`cp -f`, `rm -f` 等）
2. **手順を省略しない** — ビルド → `/Applications` インストール → LaunchAgent → 起動 → 検証の順
3. **結果を報告する** — 各ステップの成否と、最終的なメニューバー / デスクトップ / ログイン設定の状態
4. **秘密を出力しない** — `auth.json`、Keychain、トークンの中身は表示しない

---

## 前提条件

| 項目 | 要件 |
|---|---|
| OS | macOS 14 (Sonoma) 以降 |
| ツール | `git`, `swift`（Xcode Command Line Tools） |
| ネットワーク | 初回 clone と利用量 API 取得に必要 |
| CLI ログイン | 下記いずれか（複数可） |

### CLI ログイン確認（読み取りのみ）

```sh
# Codex
test -f ~/.codex/auth.json && echo "codex: ok" || echo "codex: missing (~/.codex/auth.json)"

# Claude Code
security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 && echo "claude: keychain ok" \
  || test -f ~/.claude/.credentials.json && echo "claude: file ok" || echo "claude: missing"

# Grok
test -f ~/.grok/auth.json && echo "grok: ok" || echo "grok: missing (~/.grok/auth.json)"
```

**1 つも認証がない場合** — セットアップは続行してよいが、ユーザーに該当 CLI のインストールとログインを案内すること。

---

## 手順（エージェントが実行するコマンド）

### 1. リポジトリ取得

```sh
git clone git@github.com:hibik1725/ai-usage-monitor.git
cd ai-usage-monitor
```

既にクローン済みなら `git pull` で最新化。

### 2. ワンショットセットアップ

```sh
chmod +x Scripts/setup.sh Scripts/uninstall.sh Scripts/build-app.sh Scripts/verify-widget.sh
./Scripts/setup.sh
```

`setup.sh` が行うこと:

| 処理 | 詳細 |
|---|---|
| ビルド | `./Scripts/build-app.sh` → `dist/QuotaBar.app` |
| インストール | `/Applications/QuotaBar.app` にコピー |
| ログイン時起動 | `~/Library/LaunchAgents/com.hivvv.quotabar.plist` を登録 |
| デスクトップ表示 | `defaults write com.hivvv.quotabar showDesktopPanelOnLaunch -bool true` |
| 通知テスト | 起動時テスト通知 + `--test-notification` + システム設定を開く |
| Widget 登録 | `pluginkit -a`（ad-hoc 署名では失敗することがある） |
| 起動 | `open -a /Applications/QuotaBar.app` |

### 3. 検証

```sh
# プローブ（3 社の利用量を 1 回取得）
/Applications/QuotaBar.app/Contents/MacOS/QuotaBar --probe

# Widget バンドル + スナップショット
./Scripts/verify-widget.sh

# LaunchAgent 登録確認
launchctl print "gui/$(id -u)/com.hivvv.quotabar" 2>/dev/null | head -5 \
  || launchctl list | grep quotabar

# デスクトップ表示フラグ
defaults read com.hivvv.quotabar showDesktopPanelOnLaunch

# 通知テスト
/Applications/QuotaBar.app/Contents/MacOS/QuotaBar --test-notification
```

### 4. ユーザーへの完了報告テンプレート

```text
QuotaBar のセットアップが完了しました。

✓ /Applications/QuotaBar.app をインストール
✓ ログイン時に自動起動（LaunchAgent）
✓ 起動時にデスクトップへ Medium パネルを表示
✓ 残量しきい値アラート（通知）を有効化

確認方法:
- メニューバー右上に Cx / Cl / Gk の残量% が表示される
- デスクトップにグラデーションの Medium ウィジェット風パネルが表示される
- パネルはドラッグで移動可能。メニューから表示/非表示を切り替え可能
- 通知: セットアップ直後にテスト通知が届く。以降は残量がしきい値（既定 20%）未満で通知
- 手動テスト: メニューバー → QuotaBar →「通知をテスト」

（任意）macOS ネイティブ WidgetKit ウィジェット:
  デスクトップを右クリック →「ウィジェットを編集」→ QuotaBar (Medium) を追加
  ※ ad-hoc 署名ではギャラリーに出ない場合あり。フローティングパネルが代替です。

アンインストール: ./Scripts/uninstall.sh
```

---

## 成功基準

エージェントは以下 **すべて** を満たしてから完了とすること。

- [ ] `/Applications/QuotaBar.app` が存在する
- [ ] `launchctl` に `com.hivvv.quotabar` が登録されている
- [ ] `defaults read com.hivvv.quotabar showDesktopPanelOnLaunch` が `1` または `true`
- [ ] `--probe` が少なくとも 1 プロバイダでエラーなく終了する（ログイン済みのもの）
- [ ] `~/Library/Group Containers/group.com.hivvv.quotabar/usage-snapshot.json` が存在する
- [ ] QuotaBar プロセスが起動している（`pgrep -x QuotaBar`）
- [ ] `--test-notification` が成功する、またはシステム設定で QuotaBar の通知が許可されている

---

## デスクトップ表示について

QuotaBar はデスクトップ表示を **2 通り** 提供します。セットアップでは **(A) を自動有効化** します。

| 方式 | 自動化 | 説明 |
|---|---|---|
| **(A) フローティングパネル** | ✅ `setup.sh` で有効 | ad-hoc 署名でも動作。起動時に自動表示 |
| **(B) WidgetKit (Medium)** | △ 手動追加が必要 | デスクトップ右クリック → ウィジェットを編集 → QuotaBar |

(A) は `showDesktopPanelOnLaunch` により、メニューバーアプリ起動後の初回取得完了時に `MediumQuotaView` をデスクトップへ表示します。
(B) は macOS のウィジェットギャラリーからユーザーが配置します（プログラムからの自動配置は macOS API 上不可）。

---

## ログイン時自動起動

LaunchAgent: `Scripts/com.hivvv.quotabar.plist`

```xml
ProgramArguments: /Applications/QuotaBar.app/Contents/MacOS/QuotaBar
RunAtLoad: true
KeepAlive: true
```

手動で再有効化する場合:

```sh
cp Scripts/com.hivvv.quotabar.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.hivvv.quotabar.plist
```

---

## トラブルシューティング（エージェント自己修復）

| 症状 | 対処 |
|---|---|
| `swift: command not found` | `xcode-select --install` を案内し、完了後に再実行 |
| ビルド失敗 | `rm -rf .build && ./Scripts/build-app.sh` |
| メニューバーに `!` や `--` | 該当 CLI で再ログイン。`--probe` でエラー文言を確認 |
| デスクトップパネルが出ない | `defaults write com.hivvv.quotabar showDesktopPanelOnLaunch -bool true` のあと `pkill -x QuotaBar; open -a /Applications/QuotaBar.app` |
| LaunchAgent が動かない | `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.hivvv.quotabar.plist` → `bootstrap` し直す |
| Claude Keychain エラー | Keychain Access で `Claude Code-credentials` に QuotaBar.app の常時許可を追加 |
| Widget ギャラリーに無い | 想定内（ad-hoc）。フローティングパネルを案内 |
| 通知が来ない | システム設定 → 通知 → QuotaBar を許可。メニュー「通知をテスト」で確認。Focus モードも確認 |

---

## アンインストール

```sh
./Scripts/uninstall.sh
```

---

## 参考

- 人間向け概要: [README.md](README.md)
- 本家（多プロバイダ版）: [steipete/CodexBar](https://github.com/steipete/CodexBar)