# AI Usage Monitor (QuotaBar)

> Codex / Claude Code / Grok のレート制限を、メニューバーとデスクトップに。

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-0a0a0c?style=flat-square)](https://github.com/hibik1725/ai-usage-monitor)
[![Swift 6](https://img.shields.io/badge/Swift-6-fa7343?style=flat-square)](Package.swift)
[![License: MIT](https://img.shields.io/badge/license-MIT-6e5aff?style=flat-square)](LICENSE)
[![Inspired by CodexBar](https://img.shields.io/badge/inspired%20by-CodexBar-16d3b4?style=flat-square)](https://github.com/steipete/CodexBar)

**QuotaBar** は、AI コーディング CLI が残しているローカル認証だけで 3 社の利用量を取得し、
メニューバーに常時表示する macOS 常駐アプリです。残量がしきい値を下回ると通知します。

[CodexBar](https://github.com/steipete/CodexBar)（53 プロバイダ対応のフル機能版）の取得ロジックを参考に、
**Codex・Claude Code・Grok の 3 社だけ**をクリーンに自前実装したスタンドアロン版です。
Cookie 復号・WebView スクレイプ・外部依存は使いません。

---

## Why QuotaBar?

| 課題 | QuotaBar の答え |
|---|---|
| 複数 CLI を使うと残量がバラバラ | メニューバー 1 行で 3 社の最小残量%を比較 |
| CodexBar は多機能だが重い | 3 社専用・ゼロ外部依存・Swift のみでビルド |
| デスクトップでも見たい | Medium ウィジェット（WidgetKit + フローティングパネル） |
| プライバシー | 既存 CLI セッションを流用。パスワードは保存しない |

## CodexBar との違い

| | **QuotaBar** (このリポジトリ) | **[CodexBar](https://github.com/steipete/CodexBar)** |
|---|---|---|
| プロバイダ数 | 3（Codex / Claude / Grok） | 50+ |
| 認証方式 | CLI ローカル認証のみ | OAuth / Cookie / API key / CLI など |
| 依存 | Swift 標準ライブラリのみ | フル macOS アプリ + CLI + 設定 UI |
| ビルド | Command Line Tools のみ（Xcode 不要） | Xcode / Swift 6.2+ 推奨 |
| ウィジェット | Medium（App Group スナップショット） | 複数プロバイダ対応 |
| 用途 | 個人の軽量モニタ | 本格的なマルチプロバイダハブ |

数値は CodexBar の `--source oauth`（Codex / Claude）および web 相当（Grok）と一致することを確認済みです。
QuotaBar で問題なければ CodexBar はアンインストールして構いません。

```sh
brew uninstall --cask codexbar   # Homebrew で入れている場合
```

---

## 表示

### メニューバー

```
Cx 0  Cl 18  Gk 67
```

各社の **最も残りが少ない枠**の残量%。色は緑 > 50% / 橙 20–50% / 赤 < しきい値（既定 20%）。
クリックで各枠（5h・週次・モデル別など）の詳細、リセット時刻、プラン名を表示します。

例: `codex · prolite` / `claude · Max` / `grok · SuperGrok`

### デスクトップ（Medium）

同じ Medium デザイン（グラデーション背景・ブランドアイコン・残量バー）を 2 通りで表示できます。

1. **メニュー「デスクトップウィジェットを表示」** — フローティング `NSPanel`（ad-hoc 署名でも即利用可）
2. **WidgetKit Extension** — デスクトップ右クリック →「ウィジェットを編集」→ QuotaBar を追加

Widget はメニューバーアプリが 5 分ごとに書き出す App Group スナップショットを読むだけです。
Widget 単体では Keychain / ネットワーク取得はしません。

```
~/Library/Group Containers/group.com.hivvv.quotabar/usage-snapshot.json
```

> **ad-hoc 署名のみ**の環境では `pluginkit` 登録が拒否されることがあります。
> その場合は (1) のフローティングパネルを使うか、Apple Developer ID で署名してください。

---

## 取得経路（すべてローカル認証 / Cookie 不要）

| プロバイダ | 認証ソース | エンドポイント |
|---|---|---|
| Codex | `~/.codex/auth.json` の `tokens.access_token` + `account_id` | `GET https://chatgpt.com/backend-api/wham/usage` |
| Claude | Keychain `Claude Code-credentials`（無ければ `~/.claude/.credentials.json`） | `GET https://api.anthropic.com/api/oauth/usage` |
| Grok | `~/.grok/auth.json` の OIDC scope トークン | `POST https://grok.com/...GetGrokCreditsConfig`（gRPC-Web） |

> Claude は **Claude Code の OAuth 利用量**（`claude` の `/usage` と同じ数値）です。
> claude.ai のチャット側利用量とは別枠です。

### プラン名の解決

| プロバイダ | ソース |
|---|---|
| Codex | API の `plan_type` |
| Claude | Keychain の `subscriptionType` / `rateLimitTier` |
| Grok | `auth_mode` → SuperGrok 等 |

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│  QuotaBar.app (menu bar)                                    │
│  ├─ AppDelegate — 5min poll, notifications, snapshot write  │
│  ├─ DesktopPanel — floating Medium UI (fallback)            │
│  └─ PlugIns/QuotaBarWidget.appex — WidgetKit Medium       │
└──────────────────────────┬──────────────────────────────────┘
                           │ App Group
                           ▼
              usage-snapshot.json
                           │
┌──────────────────────────┴──────────────────────────────────┐
│  QuotaBarCore                                               │
│  ├─ Auth — read ~/.codex, Keychain, ~/.grok                 │
│  ├─ Fetchers — HTTP / gRPC-Web per provider                 │
│  ├─ SnapshotStore — JSON encode/decode                      │
│  └─ WidgetUI — MediumQuotaView, WidgetTheme                 │
└─────────────────────────────────────────────────────────────┘
```

| ターゲット | 役割 |
|---|---|
| `QuotaBarCore` | モデル・認証・取得・App Group・共有 UI |
| `QuotaBar` | メニューバーアプリ本体 |
| `QuotaBarWidget` | WidgetKit 拡張（`MH_BUNDLE` で手動リンク） |

---

## 要件

- macOS 14+ (Sonoma) — WidgetKit `containerBackground` に必要
- Swift 6（Xcode Command Line Tools）
- 各 CLI でログイン済みであること:
  - [Codex CLI](https://github.com/openai/codex)（`~/.codex/auth.json`）
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code)（Keychain または `~/.claude/.credentials.json`）
  - [Grok CLI](https://github.com/xai-org/grok-cli)（`~/.grok/auth.json`）

---

## インストール / ビルド

Xcode 不要。Command Line Tools の Swift だけで完結します。

```sh
git clone git@github.com:hibik1725/ai-usage-monitor.git
cd ai-usage-monitor
./Scripts/build-app.sh          # dist/QuotaBar.app を生成（release + ad-hoc 署名）
open dist/QuotaBar.app          # 起動（初回は通知許可を承認）
cp -R dist/QuotaBar.app /Applications/   # 任意: インストール
```

### 開発用コマンド

```sh
swift run QuotaBar --probe              # 3 社を 1 回取得して終了（スナップショットも保存）
./Scripts/verify-widget.sh              # Widget バンドル + 共有スナップショットを検証
open dist/QuotaBar.app --args --show-desktop   # Medium パネルを即表示
```

### ログイン時に自動起動

```sh
cp -R dist/QuotaBar.app /Applications/
cp Scripts/com.hivvv.quotabar.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.hivvv.quotabar.plist
```

---

## 設定

`UserDefaults`（`com.hivvv.quotabar`）:

```sh
defaults write com.hivvv.quotabar alertThreshold -float 15   # しきい値を 15% に
```

ポーリング間隔は既定 5 分（`AppDelegate.pollInterval`）。

---

## macOS 権限

| 権限 | 必要な場合 |
|---|---|
| **通知** | 残量がしきい値を下回ったときのアラート |
| **Keychain** | Claude OAuth 資格情報の読み取り（macOS がプロンプト） |

QuotaBar は既知の CLI 設定パスと Keychain 項目だけを読みます。ディスク全体のスキャンはしません。

Keychain プロンプトを減らすには、Keychain Access で `Claude Code-credentials` の Access Control に
`QuotaBar.app` を「常に許可」に追加してから再起動してください。
（CodexBar の [Keychain ガイド](https://github.com/steipete/CodexBar/blob/main/docs/keychain-prompts.md) も参考になります。）

---

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| メニューバーに `--` と表示 | 該当 CLI で再ログイン。`swift run QuotaBar --probe` でエラー確認 |
| Widget がギャラリーに出ない | ad-hoc 署名の制限。フローティングパネルを使うか Developer ID で署名 |
| `pluginkit: rejected` | 同上。`./Scripts/verify-widget.sh` でバンドル種別を確認 |
| Claude だけ取得失敗 | Keychain 許可を確認。`~/.claude/.credentials.json` の有無を確認 |
| Grok が 0% のまま | `~/.grok/auth.json` のトークン期限。Grok CLI で再認証 |

---

## 関連 OSS

このプロジェクトは以下を参考・比較対象としています。

| プロジェクト | 説明 |
|---|---|
| [steipete/CodexBar](https://github.com/steipete/CodexBar) | 本家。53 プロバイダ・CLI・WidgetKit。取得ロジックの主要な参考元（MIT） |
| [ryoppippi/ccusage](https://github.com/ryoppippi/ccusage) | コスト利用量トラッキング（CodexBar もクレジット記載） |
| [enieuwy/showy-quota](https://github.com/enieuwy/showy-quota) | SketchyBar / tmux 向けクォータ表示（`codexbar serve` ベース） |
| [Finesssee/Win-CodexBar](https://github.com/Finesssee/Win-CodexBar) | Windows 版 CodexBar |

ローカル開発時に CodexBar ソースを置く場合（git 管理外）:

```sh
git clone https://github.com/steipete/CodexBar.git reference/CodexBar-Sources
```

---

## Contributing

Issue・PR 歓迎です。大きな変更の前に Issue で方針を相談してください。

1. Fork → feature ブランチ
2. `./Scripts/build-app.sh` と `swift run QuotaBar --probe` で動作確認
3. PR を作成

---

## License

[MIT](LICENSE) © 2026 [hibik1725](https://github.com/hibik1725)

Usage-fetch logic (especially Grok gRPC-Web protobuf handling and endpoint shapes) was
reimplemented with reference to [steipete/CodexBar](https://github.com/steipete/CodexBar) (MIT License).

---

## English summary

**QuotaBar** is a lightweight macOS 14+ menu bar app that monitors rate-limit usage for
**Codex**, **Claude Code**, and **Grok** using only local CLI credentials — no browser
cookies, no WebView scraping, no third-party dependencies.

- Menu bar: compact `%` per provider with color-coded thresholds and plan names
- Desktop: Medium WidgetKit widget (App Group snapshot) plus a floating panel fallback
- Build: `./Scripts/build-app.sh` with Swift Command Line Tools only (no Xcode)
- Inspired by [CodexBar](https://github.com/steipete/CodexBar); intentionally scoped to 3 providers