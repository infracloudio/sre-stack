## Case-2 Latency (Caused by mis-configured health probes)

### Diagram

![Application](https://github.com/infracloudio/sre-stack/blob/main/etc/image/scenario-1-case-2-application-arch.png?raw=true)

### Overview

- Reviews talking to ratings service for the data.
- Ratings service recently configured with the new deployment changes(Wrong readiness probe configs)
- Traffic get's increased app started scaling and adding new pods to replicaset
- Because of high wait time in readiness probe new pods take more time to become healthy
- During the same time application frequently getting high ammount of requestes
- Because of the high wait time in probe application face high latency in reviews and ratings service.
