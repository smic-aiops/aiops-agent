# CIR Auto Label 要求（Requirements）

本書は `apps/itsm_core/cir_auto_label/` の要求（What/Why）を定義します。詳細な利用方法・手順・実装は `apps/itsm_core/cir_auto_label/README.md`、`apps/itsm_core/cir_auto_label/workflows/`、`apps/itsm_core/cir_auto_label/scripts/` を正とします。

## 1. 対象

GitLab の CIR（継続的改善）Issue 起票直後に、既定ラベル（例: `ITSM/継続的改善`、`状態/New`）を自動付与する仕組み。

## 2. 目的

- 起票直後のラベル付与漏れを防ぎ、CIR の状態管理/抽出（他サブアプリ）を安定させる。
- Issue Hook → n8n の連携を標準化し、dry-run/OQ で再現できる状態を保つ。

