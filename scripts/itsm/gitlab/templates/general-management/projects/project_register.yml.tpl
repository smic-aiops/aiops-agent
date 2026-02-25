kind: project_register
projects:
  - project_id: proj_001
    name: "例: サービスカタログ整備"
    owner: "TBD"
    status: "planning" # planning|active|on_hold|done|cancelled
    start_date: "2026-03-01"
    target_end_date: "2026-06-30"
    milestone: "FY26-H1"
    goals:
      - "サービス要求の標準化"
    scope_in:
      - "テンプレ整備"
    scope_out:
      - "全社SSO統合（MVP外）"
    kpis:
      - kpi_id: "KPI-001"
        name: "月次レポート作成回数"
        target: ">= 1 / month"
    links:
      issues:
        - "{{GENERAL_MANAGEMENT_PROJECT_PATH}}#XXX"
      mrs: []
      docs:
        - "reports/monthly/2026-02.md"

