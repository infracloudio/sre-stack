Install causely 

```
causely auth login

causely agent install --cluster-name sre-stack --values causely-default-values.yaml

```


Install Dynatrace 

```
aws eks create-addon --cluster-name sre-stack --addon-name dynatrace_dynatrace-operator --addon-version v0.14.2-eksbuild.1 --region us-west-2

kubectl -n dynatrace create secret generic dynakube --from-literal="apiToken=<token>" --from-literal="dataIngestToken=<token>"

kubectl apply -f dynakube-k8s-csi.yaml

kubectl apply -f dynakube.yaml
```

Enable Istio metric ingest

```
kubectl annotate --overwrite service istiod -n istio-system \
metrics.dynatrace.com/port='15014' metrics.dynatrace.com/scrape='true'

kubectl annotate --overwrite service --all -n robot-shop \
metrics.dynatrace.com/port='15020' metrics.dynatrace.com/scrape='true' \
metrics.dynatrace.com/path="/stats/prometheus" \
metrics.dynatrace.com/filter='{
    "mode": "include",
    "names": [
      "istio_requests_total",
      "istio_tcp_received_bytes_total",
      "istio_tcp_sent_bytes_total",
      "istio_tcp_connections_closed_total",
      "istio_tcp_connections_opened_total",
      "istio_request_duration_milliseconds",
      "pilot_k8s_cfg_events"
    ]
  }'
```