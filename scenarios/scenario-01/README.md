# Scenario 1

## Hypothesis

### Add Latency between two microservices

Frontend service communicate with other down-stream services like Order, payment, user, catalouge, cart, etc. We will introduce latency between two microservices and observe the out-come on the application. Also we'll try to find those events in monitoring tools(Grafana Dashboard).

### Blast radius

To limit the blast radius we are going to use istio virtual service and destination rule.

### Observation