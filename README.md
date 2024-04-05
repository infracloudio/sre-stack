# SRE Stack
This repository provisions sufficiently-complex microservice demo applications such as:
- [instana/robot-shop](https://github.com/instana/robot-shop)
- [jaeger/hotrod](https://github.com/jaegertracing/jaeger/tree/main/examples/hotrod)

Along with standard observability tooling such as:
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) contains:
	- prometheus-operator
	- grafana
	- kube-state-metrics
- [Loki](https://github.com/grafana/helm-charts/tree/main/charts/loki-stack) 
- [Tempo](https://github.com/grafana/helm-charts/tree/main/charts/tempo)
- [Opentelemetry](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-collector)
- [Grafana/Beyla](https://github.com/grafana/beyla)
- [groundcover.com/Caretta](https://github.com/groundcover-com/caretta)

## Scenarios
`sre-stack` contains carefully crafted fault injection scenarios to effectively disrupt operations of the demo-applications.
Using this repo we create the following feedback-loop:
 - Fault-injection
 - Fault-detection using various o11y tooling
 - Root Cause Analysis using classic / advanced tools
 - Fault mitigation strategies, both long-term and short-term
 
 Available scenarios:
 - [scenario-01](scenarios/scenario-01/README.md)
 - [scenario-02](scenarios/scenario-02/README.md)
 - [scenario-03](scenarios/scenario-03/README.md)
 - [scenario-04](scenarios/scenario-04/README.md)

### Load-generators:
 - [Robot-shop](scenarios/load-gen/README.md)
 - [Rabbitmq](scenarios/scenario-04/README.md)

## Prerequisites
- [kubectl CLI](https://kubernetes.io/docs/tasks/tools/#kubectl)
- [helm CLI](https://helm.sh/docs/intro/install/)
- [git CLI](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [make (GNU make 4.3 or +)](https://www.gnu.org/software/make/)
- [jq](https://jqlang.github.io/jq/download/)
- [k3d](https://k3d.io/v5.6.0/#installation)

## Setup & Configuration
The core configuration is stored in the `.env` file.
This is consumed by the `makefile` to provision infrastructure and deploy applications.

### Configuration
Configurations are grouped in the `.env` file in self-explanatory sections. Most values are set to their sane defaults and would not
need changing for initial setup.

Core provisioning and deployment choices are expressed in the following two variables:

- `STACK_MODE = [ eks| local ]`
  - Choice of deploying the stack to either `aws/eks` or using a `k3d` cluster on local linux systems.
- `APP_STACK=[ robot-shop | hotrod | all ]`
  - Choice of deploying either or both:
    - [instana/robot-shop](https://github.com/instana/robot-shop)
    - [jaeger/hotrod](https://github.com/jaegertracing/jaeger/tree/main/examples/hotrod)

### Setup
Provisioning lifecycles are controlled by `Make` commands.
Prefix all commands with `make` keyword.

Example: `make setup`

### AWS - EKS Lifecycle Commands
For EKS based provisioning you need to setup `AWS_PROFILE` pointing to the correct AWS account. 

Following AWS credentials for the said `profile` should be added to `~/.aws/credentials`
```
[profile-name]
aws_access_key_id=*************
aws_secret_access_key=*********
```

```
EKS setup/deploy/cleanup commands:
	setup                               - End-to-end setup on EKS
	start-cluster                       - start EKS Cluster
	setup-cluster-autoscaler            - Setup node auto scaling
	setup-observability                 - Setup monitoring/observability
	setup-optional-otel                 - Setup OpenTelemetry
	setup-istio                         - Setup istio and ingress
	setup-db-rds-mysql                  - Setup RDS - mysql
	setup-rabbitmq-operator             - Setup rabbitmq-operator
	setup-robot-shop                    - Deploy robot-shop app-stack.
	setup-optional-rmq-consumer-scaling - Setup keda to scale dispatch (optional)
	setup-gateway                       - Setup Ingress gateway
	cleanup-cluster                     - Cleanup cluster
	cleanup                             - Clenaup all resources and EKS cluster
```
### Local - k3D Lifecycle Commands

Just make sure `k3d` is installed, cluster-creation and lifecycle are handled by the following commands:

```
Local (k3D) setup/deploy/cleanup commands:
	setup-local                         - Setup end-to-end stack on local k8s (k3d)
	setup-local-cluster                 - Setup local k3d cluster
	cleanup-local                       - Cleanup end-to-end stack on local k8s (k3d)
```

### Utility Commands:

```
  get-service-endpoints               -  Print exposed endpoints (works for both local/eks)
```

### Contribution Guide

We welcome contributions from the community to help improve and expand this repository. Please take a moment to review this guide before getting started.

#### How to Contribute

**Fork the Repository**: Start by forking the repository to your own GitHub account.

**Make Changes**: Ensure that your changes adhere to the project's coding conventions and style guidelines.

**Test Your Changes**: Test your changes thoroughly to ensure they work as intended and do not introduce any regressions. Here are the steps to test your changes:

1. **Setup**: If your changes involve infrastructure setup or deployment, ensure that you test it by creating an `EKS` or `k3d` cluster as specified in the above `Life Cycle Commands` section.

2. **Verification**: Verify that the application behaves as expected after your changes. Ensure there are no unexpected side effects.

3. **Logging and Screenshots**: Capture logs, screenshots, or any other evidence that demonstrates the effectiveness of your changes. This evidence will help reviewers understand the impact of your contributions.

**Submit a Pull Request**: Provide a detailed description of your changes in the pull request, including any relevant information that may help reviewers understand the purpose and impact of the changes. Include the evidence of your testing, such as logs and screenshots, to support your changes.

**NOTE** The pull request may be accepted, rejected, or require further modifications before it can be merged.
