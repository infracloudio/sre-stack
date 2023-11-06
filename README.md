# SRE Stack
This is the project to deploy infra and test automations.

## Infrastructure Pre-Req

- AWS Account
- AWS VPC with 2 Private and 2 Public
- helm CLI
- git CLI
- kubectl CLI
- make (GNU make 4.3 or +)
- hey (For load testing)

## Setup and Install in one command

### Setup all

`make setup`

## OR Setup one by one

### Start EKS cluser

`make start-cluster`

### Setup Istio

`make setup-istio`

### Setup Observability

`make setup-observability`

### Deploy application

`make deploy-app`

### Install and Setup Cluster auto scaler

`make install-asg`

### Setup Addons kiali, Jaeger, External access of Grafana and Prometheus

`make setup-addons`

### Cleanup cluster

`make cleanup-cluster`
