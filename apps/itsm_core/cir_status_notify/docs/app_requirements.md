# CIR Status Notify 要求（Requirements）

本書は `apps/itsm_core/cir_status_notify/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/itsm_core/cir_status_notify/README.md`、`apps/itsm_core/cir_status_notify/workflows/`、`apps/itsm_core/cir_status_notify/scripts/` を正とします。

## 1. 対象

GitLab Issue のステータス更新を検知し、通知や後続処理（例: 承認フロー）へ接続する仕組み。

## 2. 目的

- ステータス遷移（`状態/*`）を運用上のトリガとして利用できるようにする。
- Issue Hook → n8n の連携を標準化し、テスト（OQ）で再現できる状態を保つ。

