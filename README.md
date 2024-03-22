# SRE Stack
The objective of this repo is to demonstrate effective SRE practices through the utilization of diverse microservice-based applications such as Robot Shop and Hotrod (with plans to incorporate more in the future).

We prioritize the implementation of observability (o11y), actively introduce and address chaos, and diligently work towards mitigating its impact. This repository serves as a comprehensive hub for practicing SRE concepts.

## Pre-Reqs

- kubectl CLI
- helm CLI
- git CLI
- make (GNU make 4.3 or +)
- [jq](https://jqlang.github.io/jq/)
- k3d 

## Infrastructure and Application setup

Infrastructure and application deployment steps are encapsulated within makefile targets. All you need to do is adjust the configurations in the `.env` file

We may need to adjust two variables primarily: `STACK_MODE` and `APP_STACK`.

For `STACK_MODE`, you can choose between `eks` and `local`. The eks mode configures an EKS cluster and deploys the application onto it, while the local mode creates a k3d cluster on your local machine.

As for `APP_STACK`, you have the option of selecting `sre-stack`, `hotrod`, or `all` (to deploy all available app stacks in this repository) for deployment.

## Commands

### EKS

To provision EKS infrastructure and deploy applications:

`make setup`

To cleanup the EKS infrastructure:

`make cleanup`

### Local 

To create a k3d cluster and deploy applications:

`make setup-local`

To cleanup the k3d cluster:

`make cleanup-local`

### Retrieve All Service Endpoints

To obtain the endpoints of all services, simply execute. It will provide the endpoints based on whether you're using EKS or a local setup

`make get-services-endpoint`

