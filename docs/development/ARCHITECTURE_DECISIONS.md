# 公開準備の設計判断

- **資格情報の更新を原子的に扱う。** 同じ Security の更新でデータと端末限定の保護属性を適用する。ロック中に以前の値を返すメモリキャッシュを廃止する。端末のセキュリティ設定と OS の判断に従う。[Apple の Keychain 更新](https://developer.apple.com/documentation/security/updating-and-deleting-keychain-items)・[アクセス属性](https://developer.apple.com/documentation/security/ksecattraccessible)
- **ChatGPT アカウント連携は開発ビルドでのみ明示有効化する。** 現行コードには専用の Responses 推論経路がなく、公開形態での適格性も未確認。公開版の案内は既存 BYOK に揃え、過去に保存した連携を利用者が解除できるようにする。[公式の適用範囲](https://developers.openai.com/siwc/token-sharing-open-source)・[公式の推論経路](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- **SQLite の現行原本を維持し、移行の判断は計測に基づく。** バッファの寿命を SQLite の同期実行範囲に限定して一時コピーを減らす。件数・ID・メディアを保証できる移行が確立するまで、既存データに破壊的な移行をかけない。
- **OCR と検索は既存原本から再構築可能にする。** 画像本文は参考情報として扱う。画像への参照と取得時点の有効性、ローカル閲覧・クラウド送信の権限を検索経路に引き継ぐ。
- **会議の参加方式は停止と権限の境界を先に決める。** 調査と段階的な実装条件は [オンライン会議 Bot](../ONLINE_MEETING_BOT.md)。
