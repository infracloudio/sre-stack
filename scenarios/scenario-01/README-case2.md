## Case-2 Latency (Caused by mis-configured health probes)

### Diagram

![Application](https://github.com/infracloudio/sre-stack/blob/main/etc/image/scenario-1-case-2-application-arch.png?raw=true)

### Scenario trigger

Mis-Configuration of health probe detected during the Pod Auto-scaling.

### Overview

- Reviews talking to ratings service for the data.
- Ratings service recently configured with the new deployment changes(Wrong readiness probe configs)
- Traffic get's increased app started scaling and adding new pods to replica-set
- Because of high wait time in readiness probe new pods take more time to become healthy
- During the same time application frequently getting high amount of requests
- Because of the high wait time in probe application face high latency in reviews and ratings service.


### Steps performed to find root-cause

- Alert triggered for `error` found in metrics/logs or `latency` increased between microservices.
- Alert specific pod, deployment and service health check for `productpage`
- CLI kubectl describe deployment and pod `productpage`.
- Check logs (CLI or Grafana) `prouctpage, reviews and ratings`.
- `ratings` service pods, logs and replica-set and deployment check (Final step where we'll find mis-config cause.)

### Load testing

Load on productpage
```bash
k6 run -u 4 -d 600s - <<EOF
import http from 'k6/http';

export default function () {
    http.get('http://us-east-1.elb.amazonaws.com/productpage');
}
EOF
```

Load on ratings service direct via API
```bash
k6 run -u 5000 -d 300s - <<EOF
import http from 'k6/http';
export default function () {
    http.get('http://us-east-1.elb.amazonaws.com/ratings/0');
}
EOF
```
