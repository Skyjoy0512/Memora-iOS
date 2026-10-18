# Codex supervisor / OpenCode Go worker

BitrigのMemoraを開き、エージェントをCodexにして依頼する。Codexが設計とタスク分割を行い、OpenCode Goが隔離コピーを実装、Codexが差分レビューを行う。機械チェック、回帰テスト、シミュレーター向けの全体ビルドが通るまで完了扱いにしない。初回実装に加え修正は最大2回。

## 使い方

BitrigのCodexに「この変更をOpenCode Goワーカーへ委任して」と依頼する。Codexは対象ファイルを調べ、正確なパスを列挙して次を実行する。

```sh
/opt/homebrew/bin/python3.12 tools/supervisor/run.py \
  --task '具体的な要件と完了条件' \
  --allow-file App/Example.swift
```

`Example.swift`は説明用。実在する対象、または必要な新規ファイルに置き換える。1回の呼び出しは小さな変更に限る。

結果はWorkspaceSSDの`Development/Agents/MemoraSupervisor/run-*`に保存。`plan.json`は設計・分割、`review-N.json`はレビュー、`result.json`は最終判定、`candidate.patch`は新規ファイルも含む差分。ログは所有者だけが読める。認証情報を引数やプロンプトに書かない。

通常は合格パッチを作るところまで。`--apply`を付けると全チェック合格後、元のHEADと作業ツリーが開始時から変わっていない場合だけパッチを適用する。Codexは適用後に差分を確認し、今回のファイルだけをコミットする。pushやPR作成は含めない。既存変更がある場合は停止し、stash/reset/cleanは行わない。

UI対象は明示的なUI変更依頼のときだけ`--allow-ui`を追加する。これは画面確認の代わりにはならない。Liquid Glass、キーボード、アクセシビリティ、実機の録音などはBitrigのプレビュー/実機で別途確認し、未検証を報告する。

アプリに影響する変更を取り込んだ後は、Bitrig内の監督Codexが`bitrig preview -platform iOS`を実行し、ユーザーが見ているプレビューを更新する。今回は外部Codexセッションからの`bitrig build -list -json`が終了69（Bitrigが開始したセッションでのみ動作）を返したため、隔離コピーの検証はXcodeビルドを使う。Bitrig内からの起動とプレビュー操作は別の確認項目。

## 固定した接続

- 監督: `/Volumes/WorkspaceSSD/Development/Tools/npm-global/bin/codex`、ChatGPT認証、`gpt-5.6-sol`。ユーザーのグローバル設定を読み込まず、read-onlyで設計とレビュー。
- ワーカー: `/Users/ken/.opencode/bin/opencode` 2.0.32、`opencode-go/deepseek-v4.1-flash`、既存OpenCode認証。GoにはワークスペースのPrivacyでGlobal regionsが必要。
- Bitrigの既存OpenCode ACP: `/opt/homebrew/bin/opencode acp` 1.18.11。直接OpenCodeを選ぶ場合の接続は既存のまま。監督フローはBitrigでCodexを選んで使う。
- XcodeGen 2.46.0: WorkspaceSSD上の専用ツール。`Project.json`から使い捨てエクスポート内にXcodeプロジェクトを生成。元のBitrigビルド環境、署名、プロジェクト設定を書き換えない。

## ガードレール

- ワーカーは独立したローカルclone内で作業。リモートを削除し、専用の空設定ディレクトリでグローバル/プロジェクトのプラグイン・MCPを読み込まない。シェル・MCP・外部ディレクトリ・追加エージェント・grepを拒否。書き込みは列挙したファイルだけ。監督Codexには読み取り専用の差分調査を許可する。
- AGENTS.md / DESIGN.mdを引き継ぐ。UISegmentedControl、glassボタンとpopover/zoom、スクロール、Reduce Motion、IME、録音/STTと承認境界を保持。
- 対象外差分、symlink、Git履歴変更、設定/認証変更、CLIエラー、空の差分、形式不正レビューは停止。レビューの指摘が残っていれば不合格。
- `git diff --check`、motion policy、既存motion/loading回帰テスト、署名なしiOS Simulator全体ビルドを毎回実行。タスク固有の機能テストは監督Codexが追加で実行する。
- 回帰テストはmacOS sandbox内で実行し、専用の検証出力先とモジュールキャッシュ以外への書き込み・ネットワーク・認証ディレクトリの読み取りを拒否する。候補コードと監督のパッチ/ログは書き換えられない。Swiftマクロも同じ外側の制約下で実行する。ビルドは固定したProject.jsonから生成し、認証用環境変数を渡さない。ワーカーによるProject.jsonやビルド手順の変更は認めない。
- 最大2回の差し戻し後は停止し、候補と根拠を残す。タイムアウトは子プロセスも終了する。自動モデル切替はしない。
- OpenCodeのpermissionはツール制限でありOSサンドボックスではない。同じユーザーで実行するCLIを信頼する最小構成。未知のプラグイン等を追加した場合は再監査する。

## 接続エラー

Goの地域エラーはPrivacy設定を確認する。Codexのモデル拒否はログと`codex login status`を確認する。APIキーを表示しない。認証情報のコピーや代替プロバイダーへの自動切替はしない。

Reason Network / DeepSeek Harnessは不要。この構成はBitrigのエージェント選択を自動切替する機能ではなく、BitrigのCodexがCLIでワーカーを呼ぶ方式。
