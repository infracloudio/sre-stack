# Scenario: AZ or Datacenter zone down

## Description:

The three-tier application hosted on an AWS EKS (Elastic Kubernetes Service) cluster experienced an Availability Zone (AZ) failure. This unexpected AZ failure resulted in the disruption of the application's normal operations, impacting its availability and performance.

Since it was already using multi Availability Zone(2) spread node-group deployment few microservices and replicas were running on those AZ specific node.

### Diagram

![Application](https://github.com/infracloudio/sre-stack/blob/main/etc/image/scenario-3-application-arch.png?raw=true)
