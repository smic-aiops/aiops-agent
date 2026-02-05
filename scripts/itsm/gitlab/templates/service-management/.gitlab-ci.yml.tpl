stages:
  - cmdb_validate
  - cmdb_sync

cmdb:validate:
  stage: cmdb_validate
  image: alpine:3.19
  rules:
    - changes:
        - cmdb/**/*.md
        - scripts/cmdb/validate_cmdb.sh
      when: on_success
    - when: never
  before_script:
    - apk add --no-cache bash ripgrep
  script:
    - bash scripts/cmdb/validate_cmdb.sh --strict cmdb
  # 検証モード:
  # - Grafana 連携: `grafana` セクションがある場合に必須項目を検証
  # - AWS 監視基盤: `aws_monitoring` セクションがある場合に必須項目を検証
  # - strict: Grafana/AWS のどちらか + SLAリンク必須
  # 切替例:
  # - 非strict: `bash scripts/cmdb/validate_cmdb.sh cmdb`
  # - Grafanaのみ: `bash scripts/cmdb/validate_cmdb.sh --no-aws cmdb`
  # - AWSのみ: `bash scripts/cmdb/validate_cmdb.sh --no-grafana cmdb`

cmdb:zulip_stream_sync:
  stage: cmdb_sync
  image: alpine:3.19
  rules:
    - if: '$CI_PIPELINE_SOURCE == "schedule"'
    - changes:
        - cmdb/**/*.md
        - scripts/cmdb/sync_zulip_streams.sh
  before_script:
    - apk add --no-cache bash curl jq yq
  script:
    - bash scripts/cmdb/sync_zulip_streams.sh cmdb
