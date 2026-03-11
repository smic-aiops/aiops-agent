kind: project_plans
plans:
  - plan_id: plan_001
    project_id: proj_001
    title: "例: サービスカタログ整備（実行計画）"
    owner: "TBD"
    phases:
      - phase: 1
        name: "現状整理"
        due_date: "2026-03-15"
        deliverables:
          - "ギャップ分析レポート"
        links:
          issues:
            - "{{GENERAL_MANAGEMENT_PROJECT_PATH}}#XXX"
      - phase: 2
        name: "テンプレ整備"
        due_date: "2026-04-30"
        deliverables:
          - "Issue テンプレ"
          - "運用手順"

