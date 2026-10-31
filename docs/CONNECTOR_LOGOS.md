# コネクタの公式ブランド画像

2026-10-31: 利用者の指示で、外部サービスの識別には保存済みの公式画像を再採用。
AIPluginIcon.brandAssetNameは登録されたサービスIDだけから画像を解決し、名前から推測しない。
一覧・詳細・Ask AI候補/指定チップ・マーケットプレイスで同じ画像を使う。
ロゴは元の色と比率を維持し、サービスの画像を傾けない。GitHubは明暗別の公式画像を使用。
スキル・資料・操作のアイコンは引き続きLucide。

| サービス | 公式配布元と画像 |
| --- | --- |
| Gmail | [Google配布の製品アイコン](https://www.gstatic.com/images/branding/productlogos/gmail_2026/v2/web-64dp/logo_gmail_2026_color_2x_web_64dp.png) |
| Notion | [公式サイト](https://www.notion.com/)のapple-touch-icon・組織ロゴ: [logo-ios.png](https://www.notion.com/front-static/logo-ios.png) |
| Google Drive | [公式ブランドガイド](https://developers.google.com/workspace/drive/api/guides/branding)の配布リンク: [製品ロゴ](https://www.gstatic.com/images/branding/productlogos/drive_2026/v2/web-64dp/logo_drive_2026_color_2x_web_64dp.png) |
| GitHub | [公式ブランドキット](https://brand.github.com/foundations/logo)の[配布ZIP](https://brand.github.com/GitHub_Logos.zip)内の`GitHub_Invertocat_Black.svg`・`GitHub_Invertocat_White.svg` |
| MCP | [公式リポジトリのfavicon.svg](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/favicon.svg) |

各商標・ロゴの権利はそれぞれの権利者に帰属する。サービスの識別にのみ使用する。
Google DriveとGitHubの未対応表示は維持する。ロゴは接続済みを意味しない。
端末カレンダーはEventKitであり、Google Calendarへの直接接続ではないため、
GoogleのロゴではなくLucideのカレンダーアイコンを使用する。

## アカウントとAIプロバイダー

GoogleサインインにはGeminiマークを流用せず、[Googleのサインインガイド](https://developers.google.com/identity/branding-guidelines)で配布する
[Gマーク](https://developers.google.com/static/identity/images/g-logo.png)を使用。2026-10-31取得、元の色・比率を保ち白い台座に表示する。
AppleサインインはOS付属の`apple.logo`（iOS 16以降）をその用途に限定して使用する。
これは操作用のLucide統一とは別のブランド識別。SF Symbolの任意使用を許可する例外ではない。
AIプロバイダーの既存マークも元の色で表示し、明暗どちらでも読める白い台座に置く。
認証やコネクタの接続状態は変更しない。

## 2026-10-31 表示確認

- `bitrig preview -platform iOS`: 成功。ログ `2026-10-31T16-08-36-87b63496.log`、既存警告11件。
- デザイン回帰チェックとLucideの4検査が通過。SF直接利用の例外はAuthProviderButtonの`apple.logo`一つに限定。
- iPhone 18 Pro MaxでコネクタのGmail/Notion/MCP/Drive/GitHubをライト/ダークで目視確認。GitHubの明暗別画像も確認。
- アカウント画面のGoogle G/Appleマークを目視確認。認証ボタンは押していない。
- 実行ログに`SelfCheck failed|Fatal error`なし。終了時は元のライト表示、コネクタシートへ戻した。
- AIプロバイダーは既存全9画像の色設定を確認し、白い台座/元の描画色に統一。個々の提供元の実認証はこの変更の確認対象ではない。
