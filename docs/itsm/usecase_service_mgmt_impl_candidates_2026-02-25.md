# サービス系（設計ファミリ=service）：実装済み（根拠+自動化）一覧

- 元データ: `docs/itsm/usecase_impl_gap_report_2026-02-25_reclassified.csv`
- 設計割当: `docs/itsm/usecase_design_allocation_2026-02-25.csv`（`設計ファミリ == service`）
- 抽出条件: `再分類 == "実装済み（根拠+自動化）"`
- 件数: 180

## インシデント管理（37）
- UC-0201 / UC-GL-291: インシデント管理のSLA/目標管理（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0202 / UC-GL-292: インシデント管理のエスカレーション/連携（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0203 / UC-GL-293: インシデント管理のデータ品質の維持（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0204 / UC-GL-294: インシデント管理のナレッジの更新（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0205 / UC-GL-295: インシデント管理のレポート/振り返り（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0206 / UC-GL-296: インシデント管理のレポートの標準化（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0207 / UC-GL-297: インシデント管理の依存関係の整理（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0208 / UC-GL-298: インシデント管理の分類/優先度付け（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0209 / UC-GL-299: インシデント管理の受付/登録（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0210 / UC-GL-300: インシデント管理の品質保証/監査（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0211 / UC-GL-301: インシデント管理の実行/処理（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0212 / UC-GL-302: インシデント管理の承認/レビュー（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0213 / UC-GL-303: インシデント管理の改善施策の実施（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0214 / UC-GL-304: インシデント管理の方針/標準定義（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0215 / UC-GL-305: インシデント管理の標準テンプレートの整備（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0216 / UC-GL-306: インシデント管理の継続的改善（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0217 / UC-GL-307: インシデント管理の自動化/効率化（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0218 / UC-GL-308: インシデント管理の調査/分析（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0219 / UC-GL-309: インシデント管理の通知/コミュニケーション（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0220 / UC-GL-310: インシデント管理の運用手順の整備（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0221 / UC-GL-311: インシデント管理の関係者合意の形成（GitLab; Zulip; n8n; Grafana; cloudwatch_event_notify; aiops_agent）
- UC-0224 / UC-AIOPS-OFF-001: チャットからの緊急インシデント（Service Down）をトリアージし、候補/不足情報/次アクションを提示する（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0225 / UC-AIOPS-OFF-002: 変更依頼は承認が必要なフローへ誘導する（安易に自動実行しない）（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0226 / UC-AIOPS-OFF-003: 曖昧な依頼は推測で埋めずに確認質問へ誘導する（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0227 / UC-AIOPS-OFF-004: 監視アラート（CloudWatch 等）を受け、必要に応じて自動反応/確認/承認へ分岐する（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0228 / UC-AIOPS-OFF-005: ルーティング/エスカレーション候補を選定し、適切な対応案（ログ収集等）へ誘導する（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0229 / UC-AIOPS-OFF-006: 既知エラー/ナレッジ検索（RAG）へ誘導し、調査を支援する（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0230 / UC-AIOPS-OFF-007: フィードバック入力は運用アクションとして誤解釈せず、安全側（確認/拒否）で扱う（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0231 / UC-AIOPS-OFF-008: 意味不明/未知語の入力はフォールバック（確認/拒否）し、暴走を抑止する（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0232 / UC-AIOPS-OFF-009: プロンプトインジェクション等の攻撃入力を拒否または安全側に処理する（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0233 / UC-AIOPS-OFF-010: PII/秘密情報の混入を想定し、出力（理由等）に秘匿情報を残さない（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0234 / UC-AIOPS-OFF-011: GitLab Wiki 等のナレッジ検索を想定し、RAG 参照の意思決定（preview facts）を行う（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0235 / UC-AIOPS-OFF-012: RAG から得た候補（candidate）をプレビューに反映し、次アクションの根拠を整える（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0236 / UC-AIOPS-OFF-013: 解決済みの対応内容をナレッジ化（再利用可能なFAQ/手順/注意点）し、GitLab の docs/ 等へ記録できるように誘導する（ITIL4 テンプレ: `14_knowledge_management`）（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0237 / UC-AIOPS-OFF-015: AIOpsAgent が `auto_enqueue`（自動承認/自動実行）した場合も **Zulip 上の決定**として扱い（`/decision`）、GitLab へ証跡化し、DB（`aiops_approval_history`）に記録して `/decisions` で参照できる（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0238 / UC-AIOPS-OFF-016: ユーザー要望（例: 「○○ができるようになって」）を受領して回答し、GitLab の一般管理プロジェクトの CIR（継続的改善レジスター）＝GitLab Issue に改善機会として `New` で集約する（重複がないように登録）。運用者が `Approved` にした時に、要望を行ったユーザーに対して、チャット上で「以前のご要望（要約）は承認されたので、これから改善します。」旨のメッセージを送信する。（aiops_agent; n8n; GitLab; Zulip; Qdrant）
- UC-0239 / UC-AIOPS-OFF-014: 承認リンク（クリック）による approve/deny を **Zulip 上の決定**として扱い、証跡（承認履歴）を保存し、Zulip から `/decisions` で時系列サマリを参照できる（aiops_agent; n8n; GitLab; Zulip; Qdrant）

## サービスデスク（32）
- UC-1501 / UC-GL-312: サービスデスクのSLA/目標管理（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1502 / UC-GL-313: サービスデスクのエスカレーション/連携（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1503 / UC-GL-314: サービスデスクのデータ品質の維持（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1504 / UC-GL-315: サービスデスクのナレッジの更新（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1505 / UC-GL-316: サービスデスクのレポート/振り返り（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1506 / UC-GL-317: サービスデスクのレポートの標準化（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1507 / UC-GL-318: サービスデスクの依存関係の整理（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1508 / UC-GL-319: サービスデスクの分類/優先度付け（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1509 / UC-GL-320: サービスデスクの受付/登録（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1510 / UC-GL-321: サービスデスクの品質保証/監査（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1511 / UC-GL-322: サービスデスクの実行/処理（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1512 / UC-GL-323: サービスデスクの承認/レビュー（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1513 / UC-GL-324: サービスデスクの改善施策の実施（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1514 / UC-GL-325: サービスデスクの方針/標準定義（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1515 / UC-GL-326: サービスデスクの標準テンプレートの整備（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1516 / UC-GL-327: サービスデスクの継続的改善（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1517 / UC-GL-328: サービスデスクの自動化/効率化（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1518 / UC-GL-329: サービスデスクの調査/分析（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1519 / UC-GL-330: サービスデスクの通知/コミュニケーション（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1520 / UC-GL-331: サービスデスクの運用手順の整備（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1521 / UC-GL-332: サービスデスクの関係者合意の形成（GitLab; Zulip; n8n; workflow_manager; zulip_gitlab_issue_sync）
- UC-1525 / UC-MEN-01: GitLab Webhook を受信し、本文から `@mention` を抽出して Zulip（DM 等）へ通知する（gitlab_mention_notify; n8n; GitLab; Zulip）
- UC-1526 / UC-MEN-02: Webhook Secret を検証し、不正送信を拒否する（未設定時は fail-fast で停止する）（gitlab_mention_notify; n8n; GitLab; Zulip）
- UC-1527 / UC-MEN-03: dry-run で通知先と本文を確認し、誤検知/過通知のリスクを事前に抑制する（gitlab_mention_notify; n8n; GitLab; Zulip）
- UC-1528 / UC-MEN-04: 除外語/ユーザーマッピング/上限などのルールで過通知を抑制する（gitlab_mention_notify; n8n; GitLab; Zulip）
- UC-1529 / UC-MEN-05: （任意）GitLab API を参照して補足情報を付与し、運用者の判断材料を増やす（gitlab_mention_notify; n8n; GitLab; Zulip）
- UC-1530 / UC-ZG-03: Issue 状態（クローズ/再オープン等）を同期し、Zulip 側へ結果を通知する（Issue→会話の反映を含む）（zulip_gitlab_issue_sync; n8n; Zulip; GitLab）
- UC-1531 / UC-ZG-01: Zulip の特定 stream/topic を起点に GitLab Issue を作成し、結果を Zulip に通知する（zulip_gitlab_issue_sync; n8n; Zulip; GitLab）
- UC-1532 / UC-ZG-06: Zulip または GitLab Issue 上の「最終決定」を決定マーカーで識別し、Zulip へ通知しつつ GitLab Issue に証跡（決定ログ）を残す（最終決定: Zulip/GitLab、証跡の正: GitLab）（zulip_gitlab_issue_sync; n8n; Zulip; GitLab）
- UC-1533 / UC-ZG-02: 同一 topic の継続会話を GitLab Issue/コメントへ追記し、履歴を同期する（会話→Issue）（zulip_gitlab_issue_sync; n8n; Zulip; GitLab）
- UC-1534 / UC-ZG-04: 誤同期を抑制する（stream 名/ID 制約、マッピング/ルール、アンカー/差分同期で漏れ・重複を抑える）（zulip_gitlab_issue_sync; n8n; Zulip; GitLab）
- UC-1535 / UC-ZG-05: （任意）イベント/メトリクスを S3 へエクスポートし、日次振り返り等に利用できる形にする（zulip_gitlab_issue_sync; n8n; Zulip; GitLab）

## サービス構成管理（23）
- UC-2001 / UC-EXA-23: CMDB同期（定期）（Exastro ITA API; n8n; GitLab; Zulip）
- UC-2002 / UC-EXA-03: パラメータ管理（Exastro ITA Web / Exastro ITA API）
- UC-2003 / UC-GL-375: サービス構成管理のSLA/目標管理（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2004 / UC-GL-376: サービス構成管理のエスカレーション/連携（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2005 / UC-GL-377: サービス構成管理のデータ品質の維持（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2006 / UC-GL-378: サービス構成管理のナレッジの更新（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2007 / UC-GL-379: サービス構成管理のレポート/振り返り（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2008 / UC-GL-380: サービス構成管理のレポートの標準化（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2009 / UC-GL-381: サービス構成管理の依存関係の整理（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2010 / UC-GL-382: サービス構成管理の分類/優先度付け（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2011 / UC-GL-383: サービス構成管理の受付/登録（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2012 / UC-GL-384: サービス構成管理の品質保証/監査（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2013 / UC-GL-385: サービス構成管理の実行/処理（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2014 / UC-GL-386: サービス構成管理の承認/レビュー（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2015 / UC-GL-387: サービス構成管理の改善施策の実施（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2016 / UC-GL-388: サービス構成管理の方針/標準定義（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2017 / UC-GL-389: サービス構成管理の標準テンプレートの整備（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2018 / UC-GL-390: サービス構成管理の継続的改善（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2019 / UC-GL-391: サービス構成管理の自動化/効率化（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2020 / UC-GL-392: サービス構成管理の調査/分析（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2021 / UC-GL-393: サービス構成管理の通知/コミュニケーション（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2022 / UC-GL-394: サービス構成管理の運用手順の整備（GitLab; Exastro ITA Web / Exastro ITA API; n8n）
- UC-2023 / UC-GL-395: サービス構成管理の関係者合意の形成（GitLab; Exastro ITA Web / Exastro ITA API; n8n）

## サービスレベル管理（21）
- UC-1801 / UC-GL-333: サービスレベル管理のSLA/目標管理（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1802 / UC-GL-334: サービスレベル管理のエスカレーション/連携（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1803 / UC-GL-335: サービスレベル管理のデータ品質の維持（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1804 / UC-GL-336: サービスレベル管理のナレッジの更新（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1805 / UC-GL-337: サービスレベル管理のレポート/振り返り（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1806 / UC-GL-338: サービスレベル管理のレポートの標準化（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1807 / UC-GL-339: サービスレベル管理の依存関係の整理（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1808 / UC-GL-340: サービスレベル管理の分類/優先度付け（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1809 / UC-GL-341: サービスレベル管理の受付/登録（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1810 / UC-GL-342: サービスレベル管理の品質保証/監査（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1811 / UC-GL-343: サービスレベル管理の実行/処理（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1812 / UC-GL-344: サービスレベル管理の承認/レビュー（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1813 / UC-GL-345: サービスレベル管理の改善施策の実施（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1814 / UC-GL-346: サービスレベル管理の方針/標準定義（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1815 / UC-GL-347: サービスレベル管理の標準テンプレートの整備（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1816 / UC-GL-348: サービスレベル管理の継続的改善（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1817 / UC-GL-349: サービスレベル管理の自動化/効率化（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1818 / UC-GL-350: サービスレベル管理の調査/分析（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1819 / UC-GL-351: サービスレベル管理の通知/コミュニケーション（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1820 / UC-GL-352: サービスレベル管理の運用手順の整備（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）
- UC-1821 / UC-GL-353: サービスレベル管理の関係者合意の形成（GitLab; Grafana; n8n; gitlab_issue_metrics_sync）

## サービス継続管理（21）
- UC-2201 / UC-GL-396: サービス継続管理のSLA/目標管理（GitLab; Grafana）
- UC-2202 / UC-GL-397: サービス継続管理のエスカレーション/連携（GitLab; Grafana）
- UC-2203 / UC-GL-398: サービス継続管理のデータ品質の維持（GitLab; Grafana）
- UC-2204 / UC-GL-399: サービス継続管理のナレッジの更新（GitLab; Grafana）
- UC-2205 / UC-GL-400: サービス継続管理のレポート/振り返り（GitLab; Grafana）
- UC-2206 / UC-GL-401: サービス継続管理のレポートの標準化（GitLab; Grafana）
- UC-2207 / UC-GL-402: サービス継続管理の依存関係の整理（GitLab; Grafana）
- UC-2208 / UC-GL-403: サービス継続管理の分類/優先度付け（GitLab; Grafana）
- UC-2209 / UC-GL-404: サービス継続管理の受付/登録（GitLab; Grafana）
- UC-2210 / UC-GL-405: サービス継続管理の品質保証/監査（GitLab; Grafana）
- UC-2211 / UC-GL-406: サービス継続管理の実行/処理（GitLab; Grafana）
- UC-2212 / UC-GL-407: サービス継続管理の承認/レビュー（GitLab; Grafana）
- UC-2213 / UC-GL-408: サービス継続管理の改善施策の実施（GitLab; Grafana）
- UC-2214 / UC-GL-409: サービス継続管理の方針/標準定義（GitLab; Grafana）
- UC-2215 / UC-GL-410: サービス継続管理の標準テンプレートの整備（GitLab; Grafana）
- UC-2216 / UC-GL-411: サービス継続管理の継続的改善（GitLab; Grafana）
- UC-2217 / UC-GL-412: サービス継続管理の自動化/効率化（GitLab; Grafana）
- UC-2218 / UC-GL-413: サービス継続管理の調査/分析（GitLab; Grafana）
- UC-2219 / UC-GL-414: サービス継続管理の通知/コミュニケーション（GitLab; Grafana）
- UC-2220 / UC-GL-415: サービス継続管理の運用手順の整備（GitLab; Grafana）
- UC-2221 / UC-GL-416: サービス継続管理の関係者合意の形成（GitLab; Grafana）

## サービス設計（21）
- UC-2501 / UC-GL-417: サービス設計のSLA/目標管理（GitLab）
- UC-2502 / UC-GL-418: サービス設計のエスカレーション/連携（GitLab）
- UC-2503 / UC-GL-419: サービス設計のデータ品質の維持（GitLab）
- UC-2504 / UC-GL-420: サービス設計のナレッジの更新（GitLab）
- UC-2505 / UC-GL-421: サービス設計のレポート/振り返り（GitLab）
- UC-2506 / UC-GL-422: サービス設計のレポートの標準化（GitLab）
- UC-2507 / UC-GL-423: サービス設計の依存関係の整理（GitLab）
- UC-2508 / UC-GL-424: サービス設計の分類/優先度付け（GitLab）
- UC-2509 / UC-GL-425: サービス設計の受付/登録（GitLab）
- UC-2510 / UC-GL-426: サービス設計の品質保証/監査（GitLab）
- UC-2511 / UC-GL-427: サービス設計の実行/処理（GitLab）
- UC-2512 / UC-GL-428: サービス設計の承認/レビュー（GitLab）
- UC-2513 / UC-GL-429: サービス設計の改善施策の実施（GitLab）
- UC-2514 / UC-GL-430: サービス設計の方針/標準定義（GitLab）
- UC-2515 / UC-GL-431: サービス設計の標準テンプレートの整備（GitLab）
- UC-2516 / UC-GL-432: サービス設計の継続的改善（GitLab）
- UC-2517 / UC-GL-433: サービス設計の自動化/効率化（GitLab）
- UC-2518 / UC-GL-434: サービス設計の調査/分析（GitLab）
- UC-2519 / UC-GL-435: サービス設計の通知/コミュニケーション（GitLab）
- UC-2520 / UC-GL-436: サービス設計の運用手順の整備（GitLab）
- UC-2521 / UC-GL-437: サービス設計の関係者合意の形成（GitLab）

## リリース管理（21）
- UC-3602 / UC-GL-463: リリース管理のSLA/目標管理（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3603 / UC-GL-464: リリース管理のエスカレーション/連携（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3604 / UC-GL-465: リリース管理のデータ品質の維持（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3605 / UC-GL-466: リリース管理のナレッジの更新（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3606 / UC-GL-467: リリース管理のレポート/振り返り（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3607 / UC-GL-468: リリース管理のレポートの標準化（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3608 / UC-GL-469: リリース管理の依存関係の整理（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3609 / UC-GL-470: リリース管理の分類/優先度付け（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3610 / UC-GL-471: リリース管理の受付/登録（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3611 / UC-GL-472: リリース管理の品質保証/監査（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3612 / UC-GL-473: リリース管理の実行/処理（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3613 / UC-GL-474: リリース管理の承認/レビュー（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3614 / UC-GL-475: リリース管理の改善施策の実施（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3615 / UC-GL-476: リリース管理の方針/標準定義（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3616 / UC-GL-477: リリース管理の標準テンプレートの整備（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3617 / UC-GL-478: リリース管理の継続的改善（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3618 / UC-GL-479: リリース管理の自動化/効率化（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3619 / UC-GL-480: リリース管理の調査/分析（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3620 / UC-GL-481: リリース管理の通知/コミュニケーション（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3621 / UC-GL-482: リリース管理の運用手順の整備（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）
- UC-3622 / UC-GL-483: リリース管理の関係者合意の形成（GitLab; n8n; Exastro ITA Web / Exastro ITA API; gitlab_push_notify）

## コミュニケーション（例外処理）（1）
- UC-1201 / UC-GL-879: GitLabメンション通知の宛先解決（GitLab; n8n; Zulip; gitlab_mention_notify）

## サービスデスク; 変更管理（1）
- UC-1701 / UC-GL-460: ボード運用（GitLab）

## サービス構成管理; 変更管理（1）
- UC-2101 / UC-GL-461: ラベル運用（GitLab）

## サービス要求管理; 変更管理（1）
- UC-2401 / UC-N8N-05: 業務自動化（n8n）
