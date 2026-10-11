# YACE migration decision

The scope says: **decide YACE migration path — keep YACE (simpler) OR use
`awscloudwatchreceiver` in the collector (unified but heavier config).**

Both options are implemented below. Pick one and apply it; you do not need both.

## Option A — keep YACE

Best when: you already run YACE in prod, the CloudWatch metric list is large,
or you don't want CloudWatch metrics to participate in collector-side
redaction/tail-sampling. YACE writes directly to Prometheus; the collector
ignores it entirely.

Apply: `./option-a-keep-yace/apply.sh`

## Option B — `awscloudwatchreceiver` in the gateway

Best when: you want one ingestion backbone, consistent `k8sattributes` on AWS
metrics, or you only have a handful of CloudWatch namespaces. Heavier config
because every namespace needs an explicit `metric_name_selector` block.

Apply: `./option-b-cloudwatch-receiver/apply.sh`

## Recommendation

For this repo: **start with Option A**. It's a no-op against existing YACE
deployments and decouples the AWS migration from the rest of the work in the
parent issue. Move to Option B once the collector tiers are stable and you
have a real driver (consistent redaction across signals, multi-account
fan-out, etc.).
