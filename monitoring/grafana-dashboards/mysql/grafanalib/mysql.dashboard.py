from grafanalib.core import (
    Dashboard, TimeSeries, GaugePanel,
    Target, GridPos,
    Stat, RowPanel,
    TIME_SERIES_TARGET_FORMAT,
    Annotations, Template, Templating,
    Graph, Legend, Tooltip, XAxis, YAxes, YAxis
)

datasource = {"uid": "$datasource"}
time_series_common_params = {
    "fillOpacity": 9,
    "lineInterpolation": "smooth",
    "lineWidth": 2,
    "pointSize": 0,
    "stacking": { "group": "A", "mode": "none" },
    "thresholds": {
        "mode": "absolute",
        "steps": [
            {
            "color": "green",
            "value": "null"
            },
            {
            "color": "red",
            "value": "80"
            }
        ]
    }
}
time_series_target_params = {
    "datasource": datasource,
    "format": TIME_SERIES_TARGET_FORMAT,
    "interval": "1m",
    "intervalFactor": 1,
    "refId": "A",
    "step": 20,
}

def get_time_series_panel(title, exp, legend, gridpos):
    return  TimeSeries(
            title=title,
            targets=[
                Target(
                    expr=exp,
                    legendFormat=legend,
                    **time_series_target_params
                ),
            ],
            gridPos=GridPos(**gridpos),
            **time_series_common_params,
        )

dashboard = Dashboard(
    title="MySQL Dashboard",
    description="Prometheus MySQL Exporter with preconfigured dashboards, alerting rules, and recording rules.",
    tags=[
        'mysql'
    ],
    timezone="",
    annotations=Annotations([
        {
            "builtIn": "1",
            "datasource": {
            "type": "datasource",
            "uid": "grafana"
            },
            "enable": "true",
            "hide": "true",
            "iconColor": "rgba(0, 211, 255, 1)",
            "name": "Annotations & Alerts",
            "type": "dashboard"
        }
    ]),
    panels=[
        RowPanel(title="System Status", collapsed=False, targets=[{
                "datasource": {
                "uid": "$datasource"
                    },
                "refId": "A"
                }
            ],
            gridPos=GridPos(h=1, w=24, x=0, y=0)
        ),
        Stat(
            title="Uptime",
            dataSource="default",
            decimals=1,
            mappings=[],
            orientation="horizontal",
            reduceCalc="mean",
            thresholdType="absolute",
            graphMode="none",
            format="s",
            thresholds=[
                {
                    "color": "rgba(245, 54, 54, 0.9)",
                    "value": "null"
                },
                {
                    "color": "rgba(237, 129, 40, 0.89)",
                    "value": "300"
                },
                {
                    "color": "rgba(50, 172, 45, 0.97)",
                    "value": "3600"
                }
            ],
            targets=[
                Target(
                    datasource='prometheus',
                    expr='mysql_global_status_uptime{job=~\"$job\", instance=~\"$instance\"}',
                    format=TIME_SERIES_TARGET_FORMAT,
                    interval="1m",
                    intervalFactor=1,
                    legendFormat="{{ instance }}",
                    refId="A",
                    step=300,
                    metric="",
                ),
            ],
            gridPos=GridPos(h=3, w=8, x=0, y=1),
        ),
        Stat(
            title="Current QPS",
            dataSource=datasource,
            description="**Current QPS**\n\nBased on the queries reported by MySQL's ``SHOW STATUS`` command, it is the number of statements executed by the server within the last second. This variable includes statements executed within stored programs, unlike the Questions variable. It does not count \n``COM_PING`` or ``COM_STATISTICS`` commands.",
            decimals=2,
            mappings=[],
            orientation="horizontal",
            reduceCalc="mean",
            thresholdType="absolute",
            graphMode="area",
            format="short",
            maxDataPoints=100,
            thresholds=[
                {
                    "color": "rgba(245, 54, 54, 0.9)",
                    "value": "null"
                },
                {
                    "color": "rgba(237, 129, 40, 0.89)",
                    "value": "35"
                },
                {
                    "color": "rgba(50, 172, 45, 0.97)",
                    "value": "75"
                }
            ],
            links=[
                {
                "targetBlank": True,
                "title": "MySQL Server Status Variables",
                "url": "https://dev.mysql.com/doc/refman/5.7/en/server-status-variables.html#statvar_Queries"
                }
            ],
            targets=[
                Target(
                    datasource={
                        "uid": "$datasource"
                    },
                    expr='rate(mysql_global_status_queries{job=~\"$job\", instance=~\"$instance\"}[$__interval])',
                    format=TIME_SERIES_TARGET_FORMAT,
                    interval="1m",
                    intervalFactor=1,
                    legendFormat="{{ instance }}",
                    refId="A",
                    step=20,
                    metric="",
                ),
            ],
            gridPos=GridPos(h=3, w=8, x=8, y=1),
        ),
        Stat(
            title="InnoDB Buffer Pool",
            dataSource=datasource,
            description="**InnoDB Buffer Pool Size**\n\nInnoDB maintains a storage area called the buffer pool for caching data and indexes in memory.  Knowing how the InnoDB buffer pool works, and taking advantage of it to keep frequently accessed data in memory, is one of the most important aspects of MySQL tuning. The goal is to keep the working set in memory. In most cases, this should be between 60%-90% of available memory on a dedicated database host, but depends on many factors.",
            decimals=0,
            mappings=[],
            orientation="horizontal",
            reduceCalc="mean",
            thresholdType="absolute",
            graphMode="none",
            format="bytes",
            maxDataPoints=100,
            thresholds=[
                {
                    "color": "rgba(50, 172, 45, 0.97)",
                    "value": "null"
                },
                {
                    "color": "rgba(237, 129, 40, 0.89)",
                    "value": "90"
                },
                {
                    "color": "rgba(245, 54, 54, 0.9)",
                    "value": "95"
                }
            ],
            links=[
                {
                    "targetBlank": True,
                    "title": "Tuning the InnoDB Buffer Pool Size",
                    "url": "https://www.percona.com/blog/2015/06/02/80-ram-tune-innodb_buffer_pool_size/"
                }
            ],
            targets=[
                Target(
                    datasource={
                        "uid": "$datasource"
                    },
                    expr='mysql_global_variables_innodb_buffer_pool_size{job=~\"$job\", instance=~\"$instance\"}',
                    format=TIME_SERIES_TARGET_FORMAT,
                    interval="1m",
                    intervalFactor=1,
                    legendFormat="{{ instance }}",
                    refId="A",
                    step=300,
                    metric="",
                ),
            ],
            gridPos=GridPos(h=3, w=8, x=16, y=1),
        ),
        RowPanel(title="Connections", collapsed=False, targets=[{
                "datasource": {
                "uid": "$datasource"
                    },
                "refId": "A"
                }
            ],
            gridPos=GridPos(h=1, w=24, x=0, y=4)
        ),
        Graph(
            dataSource=datasource,
            title="MySQL Connections",
            description="**Max Connections** \n\nMax Connections is the maximum permitted number of simultaneous client connections. By default, this is 151. Increasing this value increases the number of file descriptors that mysqld requires. If the required number of descriptors are not available, the server reduces the value of Max Connections.\n\nmysqld actually permits Max Connections + 1 clients to connect. The extra connection is reserved for use by accounts that have the SUPER privilege, such as root.\n\nMax Used Connections is the maximum number of connections that have been in use simultaneously since the server started.\n\nConnections is the number of connection attempts (successful or not) to the MySQL server.",
            fill=2,
            percentage=False,
            points=False,
            lineWidth=2,
            legend=Legend(
                alignAsTable= True,
                avg= True,
                current= False,
                max= True,
                min= True,
                show= True,
                sort= "avg",
                sortDesc= True,
                total= False,
                values= True
            ),
            tooltip=Tooltip(
                msResolution=False,
                shared=True,
                sort=0,
                valueType="cumulative"
            ),
            xAxis=XAxis(
                mode= "time",
                show= True,
                values= []
            ),
            yAxes=YAxes(                
                left=YAxis(
                    format= "short",
                    label= "",
                    logBase= 1,
                    min= 0,
                    show= True
                ),
                right=YAxis(
                    format= "short",
                    label= "",
                    logBase= 1,
                    min= 0,
                    show= True
                )
            ),
            links=[
                {
                    "targetBlank": "true",
                    "title": "MySQL Server System Variables",
                    "url": "https://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html#sysvar_max_connections"
                }
            ],
            targets=[
                Target(
                    datasource=datasource,
                    expr='sum(max_over_time(mysql_global_status_threads_connected{job=~\"$job\", instance=~\"$instance\"}[$__interval]))',
                    format=TIME_SERIES_TARGET_FORMAT,
                    interval="1m",
                    intervalFactor=1,
                    legendFormat="Connections",
                    refId="A",
                    step=20,
                    metric="",
                ),
                Target(
                    datasource=datasource,
                    expr='sum(mysql_global_status_max_used_connections{job=~\"$job\", instance=~\"$instance\"})',
                    format=TIME_SERIES_TARGET_FORMAT,
                    interval="1m",
                    intervalFactor=1,
                    legendFormat="Max Used Connections",
                    refId="C",
                    step=20,
                    metric="",
                ),
                Target(
                    datasource=datasource,
                    expr='sum(mysql_global_variables_max_connections{job=~\"$job\", instance=~\"$instance\"})',
                    format=TIME_SERIES_TARGET_FORMAT,
                    interval="1m",
                    intervalFactor=1,
                    legendFormat="Max Connections",
                    refId="B",
                    step=20,
                    metric="",
                ),
            ],
            gridPos=GridPos(h=7, w=12, x=0, y=5),
        ),
        Graph(
            dataSource=datasource,
            title="MySQL Client Thread Activity",
            description="**MySQL Active Threads**\n\nThreads Connected is the number of open connections, while Threads Running is the number of threads not sleeping.",
            fill=2,
            percentage=False,
            points=False,
            lineWidth=2,
            legend=Legend(
                alignAsTable= True,
                avg= True,
                current= False,
                max= True,
                min= True,
                show= True,
                rightSide=False,
                sort= "avg",
                sortDesc= True,
                total= False,
                values= True
            ),
            tooltip=Tooltip(
                msResolution=False,
                shared=True,
                sort=0,
                valueType="individual"
            ),
            xAxis=XAxis(
                mode= "time",
                show= True,
                values= ["total"]
            ),
            yAxes=YAxes(                
                left=YAxis(
                    format= "short",
                    label= "Threads",
                    logBase= 1,
                    min= 0,
                    show= True
                ),
                right=YAxis(
                    format= "short",
                    label= "",
                    logBase= 1,
                    min= 0,
                    show= True
                )
            ),
            seriesOverrides=[
                {
                    "alias": "Peak Threads Running",
                    "color": "#E24D42",
                    "lines": "false",
                    "pointradius": 1,
                    "points": "true"
                },
                {
                    "alias": "Peak Threads Connected",
                    "color": "#1F78C1"
                },
                {
                    "alias": "Avg Threads Running",
                    "color": "#EAB839"
                }
            ],
            targets=[
                Target(
                    datasource=datasource,
                    expr='sum(max_over_time(mysql_global_status_threads_connected{job=~\"$job\", instance=~\"$instance\"}[$__interval]))',
                    format=TIME_SERIES_TARGET_FORMAT,
                    interval="1m",
                    intervalFactor=1,
                    legendFormat="Peak Threads Connected",
                    refId="A",
                    step=20,
                    metric="",
                ),
                Target(
                    datasource=datasource,
                    expr='sum(max_over_time(mysql_global_status_threads_running{job=~"$job", instance=~"$instance"}[$__interval]))',
                    format=TIME_SERIES_TARGET_FORMAT,
                    interval="1m",
                    intervalFactor=1,
                    legendFormat="Peak Threads Running",
                    refId="B",
                    step=20,
                    metric="",
                ),
                Target(
                    datasource=datasource,
                    expr='sum(avg_over_time(mysql_global_status_threads_running{job=~"$job", instance=~"$instance"}[$__interval]))',
                    format=TIME_SERIES_TARGET_FORMAT,
                    interval="1m",
                    intervalFactor=1,
                    legendFormat="Avg Threads Running",
                    refId="C",
                    step=20,
                    metric="",
                ),
            ],
            gridPos=GridPos(h=7, w=12, x=12, y=5),
        ),
        TimeSeries(
            title="MySQL connection error",
            targets=[
                Target(
                    expr='sum(rate(mysql_global_status_connection_errors_total[5m]))',
                    legendFormat="Connection errors",
                    **time_series_target_params
                ),
            ],
            gridPos=GridPos(h=6, w=12, x=0, y=12),
            **time_series_common_params,
        ),
        TimeSeries(
            title="MySQL Connection Usage",
            targets=[
                Target(
                    expr='100 * mysql_global_status_threads_connected / mysql_global_variables_max_connections',
                    legendFormat="Connection Usage %",
                    **time_series_target_params
                ),
            ],
            gridPos=GridPos(h=6, w=12, x=12, y=12),
            **time_series_common_params,
        ),
        TimeSeries(
            title="MySQL Memory Usage vs. Limit",
            targets=[
                Target(
                    legendFormat="Memory Usage (GB)",
                    expr='sum by (namespace,pod,container)\n    (\n        (container_memory_usage_bytes{namespace=\"robot-shop\", container=\"mysql\"} -  \n        on (namespace,pod,container)\n        avg by (namespace,pod,container) (kube_pod_container_resource_limits{resource=\"memory\", namespace=\"robot-shop\", container=\"mysql\"})\n        )\n        * -1 >0 \n    ) / (1024*1024*1024)',
                    **time_series_target_params
                ),
            ],
            gridPos=GridPos(h=6, w=12, x=0, y=18),
            **time_series_common_params,
        ),
        RowPanel(title="Cache", collapsed=False, targets=[{
                        "datasource": {
                        "uid": "$datasource"
                            },
                        "refId": "A"
                        }
                    ],
                    gridPos=GridPos(h=1, w=24, x=0, y=24)
                ),
        TimeSeries(
            title="Cache hit rate",
            targets=[
                Target(
                    expr='rate(mysql_global_status_table_open_cache_hits{job=~\"$job\", instance=~\"$instance\"}[5m]) /\n(rate(mysql_global_status_table_open_cache_hits{job=~\"$job\", instance=~\"$instance\"}[5m]) + rate(mysql_global_status_table_open_cache_misses{job=~\"$job\", instance=~\"$instance\"}[5m]))',
                    legendFormat="avg cache hit",
                    **time_series_target_params
                ),
            ],
            gridPos=GridPos(h=8, w=12, x=0, y=24),
            **time_series_common_params,
        ),
        TimeSeries(
            title="InnoDB Buffer Pool",
            targets=[
                Target(
                    expr='(rate(mysql_global_status_innodb_buffer_pool_read_requests[5m]) -\nrate(mysql_global_status_innodb_buffer_pool_reads[5m])) / rate(mysql_global_status_innodb_buffer_pool_read_requests[5m])',
                    legendFormat="Buffer Pool Hit Ratio (%)",
                    **time_series_target_params
                ),
            ],
            gridPos=GridPos(h=8, w=12, x=12, y=25),
            **time_series_common_params,
        ),
        RowPanel(title="Table Locks", collapsed=False, targets=[{
                        "datasource": {**datasource},
                        "refId": "A"
                        }
                    ],
                    gridPos=GridPos(h=1, w=24, x=0, y=24)
                ),
        TimeSeries(
            title="MySQL Questions",
            description="**MySQL Questions**\n\nThe number of statements executed by the server. This includes only statements sent to the server by clients and not statements executed within stored programs, unlike the Queries used in the QPS calculation. \n\nThis variable does not count the following commands:\n* ``COM_PING``\n* ``COM_STATISTICS``\n* ``COM_STMT_PREPARE``\n* ``COM_STMT_CLOSE``\n* ``COM_STMT_RESET``",
            targets=[
                Target(
                    expr='rate(mysql_global_status_questions{job=~\"$job\", instance=~\"$instance\"}[$__interval])',
                    legendFormat="Buffer Pool Hit Ratio (%)",
                    **time_series_target_params
                ),
            ],
            gridPos=GridPos(h=8, w=12, x=12, y=25),
            **time_series_common_params,
        )
    ],
    templating=Templating(
        [
            Template(
                name="datasource",
                query="prometheus",
                type="datasource",
                includeAll=False,
                multi=False,
                hide=0,
                refresh=1,
                regex="",
                options=[],
            ),
            Template(
                name="job",
                label="Job",
                query="label_values(mysql_up, job)",
                type="query",
                includeAll=True,
                multi=True,
                hide=0,
                refresh=1,
                regex="",
                options=[],
                dataSource={"type": "prometheus", "uid": "$datasource"}
            ),
            Template(
                name="instance",
                label="Instance",
                query="label_values(mysql_up, instance)",
                type="query",
                includeAll=True,
                multi=True,
                hide=0,
                refresh=1,
                regex="",
                options=[],
                dataSource={"type": "prometheus", "uid": "$datasource"}
        )
        ]
    ),
).auto_panel_ids()