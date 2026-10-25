# ローカル法人ライセンスの整合性（2026-10-26）

## 修正済み

P1: `MemoraModel+Plans.activateLicense` / `removeLicense` がKeychain書き込み・削除のBoolを無視していた。失敗時にもメモリとUserDefaultsだけ切り替わり、再起動すると以前の状態に戻る。

両方ともKeychain成功後だけメモリと設定を更新し、失敗時は型付きstorage errorで旧コード・旧状態を保持する。削除エラーも有効ライセンス画面で表示し、成功と誤認させない。起動時のisSubscribedは古いBoolでなく、保存済みplanと再検証済みlicenseから再計算する。署名検証・期限判定・保存キー・既存データは変更しない。無効な保存コードを自動削除しない。

これはローカルライセンスであり、StoreKit課金・契約・サーバー側権限の接続ではない。

## 検証

`bash tools/checks/run-license-persistence-checks.sh`: Pass。実際のモデルextensionと実MemoraLicenseに、失敗注入可能なKeychain/検証器/設定fixtureを接続。初回保存失敗、置換失敗、削除失敗、成功後再読込、期限切れ拒否、既存コード保持、個人planへのfallbackをassert。実Keychainのロック/OSStatusや実署名コードの再起動E2EはNot Run。

Debug Simulatorビルド: Pass。最初の修正でObservable初期化前のself読み取りを検出したため、読み込んだlocal値から初期状態を組み立てる形へ修正し再ビルドPass。ライセンスコードや秘密を診断ログに追加していない。
