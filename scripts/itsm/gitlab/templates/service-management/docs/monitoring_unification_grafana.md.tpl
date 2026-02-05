# Grafana に統一するためのガイド

## 目的
- 監視の参照先を Grafana に統一し、判断根拠を一本化する

## 方針
- GitLab は一次記録、Grafana は状態参照の責務分離を維持する
- AWS 監視基盤（CloudWatch など）はデータソースとして利用し、参照は Grafana に集約する

## 手順（最小）
1. Grafana に CloudWatch データソースを追加する
2. AWS の主要指標を Grafana ダッシュボードに移植する
3. [`docs/sla_master.md`](sla_master.md) の参照ダッシュボードを Grafana に更新する
4. CMDB の `grafana` セクションを更新し、UID/PromQL/対象メトリクス/集計期間も整備する
5. `aws_monitoring` は「参考」扱いにする
6. Issue/レポートの参照リンクを Grafana に統一する

## データソース設定（共通）
- Grafana 側でデータソースを先に作成しておく（本テンプレの CI はダッシュボードのみ再生成）
- CMDB の `grafana.usecase_dashboards[].data_sources` に使用するデータソース名/種別を記載
- 各パネルは `data_source` で参照名を一致させる
- 権限は「最小権限」で付与し、読み取り専用ロールを基本とする

## AWS 監視基盤 → Grafana（CloudWatch → S3 → Athena 前提）
### アーキテクチャ
- CloudWatch Logs の S3 集約は sulu のみに限定し、Athena で集計
- Grafana からは Athena データソースのみを参照（CloudWatch 直接参照は行わない）

### 手順
1. sulu の CloudWatch Logs のエクスポート先 S3 バケットを用意
2. Glue テーブルを作成し、Athena でクエリ可能にする
3. Grafana のデータソースで `Athena` を追加（S3 出力バケット/Workgroup を設定）
4. パネルで SQL を定義し、SLA/SLO 集計に利用

## Google Cloud 監視基盤 → Grafana
### Cloud Monitoring
1. GCP でサービスアカウントを作成（Monitoring Viewer/Logging Viewer など）
2. サービスアカウント鍵（JSON）を作成
3. Grafana のデータソースで `Google Cloud Monitoring` を追加
4. プロジェクト ID を指定し、指標/ログを選択

## Azure 監視基盤 → Grafana
### Azure Monitor
1. Azure AD にアプリ登録し、Client ID/Secret を発行
2. サブスクリプション/リソースグループへ Reader 権限を付与
3. Grafana のデータソースで `Azure Monitor` を追加
4. Tenant ID/Client ID/Client Secret/Subscription ID を設定

## IDC フロンティア 監視基盤 → Grafana
### 汎用パターン（Prometheus/OpenTelemetry）
1. 監視対象に Exporter を配置（Prometheus/OpenTelemetry/SNMP など）
2. 収集先として Prometheus/OTel Collector を用意
3. Grafana のデータソースで `Prometheus` もしくは `Loki/Tempo` を追加
4. メトリクス/ログ/トレースをパネルで参照

## さくらのクラウド 監視基盤 → Grafana
### 汎用パターン（Prometheus/OpenTelemetry）
1. 監視 API/ログ/SNMP の出力を Exporter で収集
2. Prometheus/OTel Collector へ集約
3. Grafana データソースを `Prometheus` として登録
4. パネルで CPU/メモリ/ネットワーク/ディスクなどを可視化

## 移行パターン（CloudWatch → Athena → Grafana）
- 目的: CloudWatch Logs は sulu のみを Athena で集計し、Grafana に集約
- 手順例:
  1. sulu の CloudWatch Logs を S3 へエクスポート（定期）
  2. Athena で外部テーブルを作成し、SLA/SLO 集計クエリを作成
  3. Grafana の Athena データソースを追加し、ダッシュボードを構築
4. [`docs/sla_master.md`](sla_master.md) の算出元/クエリを Athena に統一
  5. CMDB の `grafana` 参照を更新し、AWS 参照は補助として残す

## 移行チェックリスト
- [ ] 可用性/エラーバジェット/レイテンシ p95 が Grafana で確認できる
- [ ] SLA/SLO の定義が [`docs/sla_master.md`](sla_master.md) に反映されている
- [ ] CMDB のリンクが Grafana に統一されている
- [ ] CMDB に UID/PromQL/対象メトリクス/集計期間が記載されている
- [ ] 逸脱アラートが Grafana → n8n → GitLab で起票される

## strict モードのメリット/デメリット
- メリット: 監視導線の未整備を CI で早期検知できる
- メリット: Grafana/AWS のどちらかが必須となり運用の抜け漏れが減る
- デメリット: 監視整備中のサービスが一時的にブロックされる
- デメリット: PoC/暫定運用の柔軟性が下がる

## CI 検証の確認手順
1. `.gitlab-ci.yml` に CMDB 検証ジョブがあることを確認する
2. CMDB の更新コミットを作成してパイプラインを実行する
3. `cmdb:validate` が通過し、必須項目の欠落がないことを確認する

## 補足
- AWS 側のダッシュボードは監査/参考用に残してよい
- 将来的に不要なら `aws_monitoring` セクションを削除する
