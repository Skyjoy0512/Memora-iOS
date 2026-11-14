# モデル・プロバイダー能力（2026-11-14調査）

「送受信経路の実装」「公式API仕様」「実モデルでの動作確認」を分ける。今回の実API確認は全モデル未実施。未知のモデル/カスタムendpointへ他社専用fieldを流用しない。能力探索の課金リクエストを出さない。

| 経路 | 現在のアプリ実装 | 推論制御 | cache | 容量の扱い |
|---|---|---|---|---|
| DeepSeek公式 | OpenAI互換Chat Completions + SSE | 既存のexact ID 2件のみreview済み。標準設定は変更しない | サーバー自動。ヒットcounter受信可能 | [公式表](https://api-docs.deepseek.com/quick_start/pricing/)は2件とも1M context / 最大384K output。実際の予約はrequest設定と別に計画する必要あり |
| OpenAI公式 | Chat Completions + SSE | 要約の独自effort送信は未実装。provider既定のまま | 自動cacheの利用はprovider側。明示TTLは送らない | [Sol](https://developers.openai.com/api/docs/models/gpt-6-sol), [Luna](https://developers.openai.com/api/docs/models/gpt-6-luna), [Astra](https://developers.openai.com/api/docs/models/gpt-6-astra)を確認。endpointごとの制約を維持 |
| Anthropic | Messages + SSE | 要約のthinking制御は未実装 | read/write usage取得可能。cache_controlは未送信 | アプリ出力上限16Kを維持。新モデルの[公式一覧](https://platform.claude.com/docs/en/models/overview)の容量を古いaliasへ無条件適用しない |
| Google Gemini | [OpenAI互換endpoint](https://ai.google.dev/gemini-api/docs/openai) + SSE | 要約のGemini固有制御は未実装 | native cachedContent管理は未実装 | native APIと互換endpointの能力を同一視しない |
| OpenRouter | 互換Chat Completions + SSE | downstreamの仕様は未知 | downstreamに依存 | モデル名の接頭辞だけで公式providerの能力を継承させない |
| Kimi / xAI / Mistral / Qwen | 各社互換Chat Completions + SSE | 要約の固有制御は未実装 | 個別仕様は未確定 | 容量・RPM・TPM・価格は未確定 |
| custom / OpenAI互換 | LLMSelectionのendpoint上書きは可能。一般の登録UIはprovider + modelIDのみで、任意endpoint編集は未実装 | unknown。推測fieldなし | unknown | 未知容量は保守的な計画。エラー時のモデル切替なし |
| Apple Foundation Models | 実装済みguided generation、端末内 | 既存設定を維持 | クラウドcacheなし | `SystemLanguageModel.contextSize`、逐次処理。外部fallbackなし |
| 将来のlocal LLM | preferenceのみ | unsupported（実行エンジン未実装） | 未実装 | 未実装 |
| Memora Intelligence | サーバー未接続 | サーバー契約未確定 | 未確定 | BYOKの公式DeepSeek扱いにしない |

## 実装する能力モデル

各能力はsupported / unsupported / unknown。context、出力上限、tokenizer、schema/JSON、usage、reasoning、cache方式、並列、RPM/TPM、価格、local/externalの属性を独立して持つ。公式の一般上限と利用者アカウントのrate limitは別であり、公式モデルでもアカウントのRPM/TPMはunknownになり得る。

JSON Schemaを利用できる公式モデルでも、利用者の未知endpointに同じパラメーターを送らない。tokenizer不明時の推定を請求token数として保存しない。cache fee・単価が不明なら費用はnull。推論量を並列数に連動させない。モデルの選択や認証情報を能力判定で変更しない。
