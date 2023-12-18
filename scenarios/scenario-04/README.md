# Scenario: 

During this simulation, we stress test RabbitMQ by overloading the order queue, surpassing the connection limit. Consequently, the payment service attempts to reconnect, leading to a strain on RabbitMQ cluster, ultimately causing OOMKilled.


## Creating this Scenario:

To reproduce this scenario, we adjust the resource allocation of the RabbitMQ cluster as specified below. Subsequently, we deploy a RabbitMQ load generator, facilitating the publication of messages to the order queue at a rate of approximately 400 publishes per second.

```
    requests:
      cpu: 100m
      memory: 50Mi
    limits:
      cpu: 200m
      memory: 200Mi
```


### Mitigation

[WIP]:

Use KEDA (Kubernetes-based Event-Driven Autoscaling) 