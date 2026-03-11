# ITSM Bootstrap docs

`apps/itsm_core/bootstrap/scripts/itsm_bootstrap_realms.sh` による GitLab 反映（bootstrap）の仕様・運用・手順を置くためのディレクトリです。

## 標準ドキュメント（最小）
- Requirements: `apps/itsm_core/bootstrap/docs/app_requirements.md`
- AIS（N/A）: `apps/itsm_core/bootstrap/docs/cs/ai_behavior_spec.md`
- DQ/IQ/OQ/PQ: `apps/itsm_core/bootstrap/docs/{dq,iq,oq,pq}/*.md`
- Usage: `apps/itsm_core/bootstrap/docs/usage/README.md`

## 収録ドキュメント
- `docs/itsm/itsm-platform.md`: サービス運用基盤の方針（ツール分担/境界/ユースケース定義の正本）
- `cir_continual_improvement_flow.md`: CIR（継続的改善）運用フロー（Approved CIR → UC-* 抽出を含む）
- `usecase_design_impl_gap_summary_2026-02-26.md`: ユースケース設計/実装ギャップの自動抽出サマリ
- `data-model.md`: ITSM コア（SoR）の統合データモデル（テーブル/参照/ACL）
- `data-retention.md`: アーカイブ/保持期間/削除/匿名化（MVP 方針）
- `itsm-core-feature-status.md`: ITSM コア（SoR）機能一覧と実装状況
- `api.md`: ITSM Core API（設計メモ / 予定）
- `cloudwatch_alarm_to_aiops_agent.md`: CloudWatch Alarm → AIOps Agent（n8n）通知
- `mention_user_mapping.md`: GitLabメンション→ユーザー対応表（テンプレ）
