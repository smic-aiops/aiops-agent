kind: risk_register
risks:
  - risk_id: RISK-001
    title: "例: 運用属人化（承認フローが人依存）"
    description: "TBD"
    category: "process" # process|security|compliance|availability|cost|other
    impact: "high"      # low|medium|high
    likelihood: "medium" # low|medium|high
    owner_role: "operations"
    status: "open"      # open|mitigating|accepted|closed
    due_date: "2026-03-31"
    mitigations:
      - "Issue で承認手順を固定し、MR で台帳反映"
    links:
      issues:
        - "{{GENERAL_MANAGEMENT_PROJECT_PATH}}#XXX"
      mrs: []

