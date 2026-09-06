local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

local title = "Prometheus MySQL Exporter with preconfigured dashboards, alerting rules, and recording rules.";

g.dashboard.new('MySQL Dashboard')
+ g.dashboard.withTitle("MySQL Dashboard")
+ g.dashboard.withUid('mysql-grafonnet-demo')
+ g.dashboard.withDescription(title)
+ g.dashboard.graphTooltip.withSharedCrosshair()
+ g.dashboard.withPanels([
//   g.panel.timeSeries.new('Requests / sec')
//   + g.panel.timeSeries.queryOptions.withTargets([
//     g.query.prometheus.new(
//       'mimir',
//       'sum by (status_code) (rate(request_duration_seconds_count{job=~".*/faro-api"}[$__rate_interval]))',
//     ),
//   ])
//   + g.panel.timeSeries.standardOptions.withUnit('reqps')
//   + g.panel.timeSeries.gridPos.withW(24)
//   + g.panel.timeSeries.gridPos.withH(8),
  + g.panel.row.new("System Status")
  + g.panel.row.withCollapsed(false)
  + g.panel.row.withGridPos(0)
//   + g.panel.stat.new('')
])

