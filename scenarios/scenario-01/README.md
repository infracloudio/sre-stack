# Scenario: Downstream API/Application performance degradation

## Description:

This is a three-tier application comprising a web frontend, a backend service, and the integration of third-party APIs. One day, the backend service encountered problems when attempting to perform HTTP GET and POST requests to interact with external third-party APIs, disrupting the normal operation of the application.

Due to this frontend was unable to load that part of the application from the backend service. These lead to cascading failure due to an outage at 3rd party API platform.

### Diagram

![Application](https://github.com/infracloudio/sre-stack/blob/main/etc/image/scenario-1-application-arch.png?raw=true)

## How did we detect outage?

This was detected via the QA/NOC team when they were doing regular testing of the product and platform. They started facing this issue on the Application web UI and then reported it to the platform engineering team.

The Platform engineering team started checking on Monitoring dashboards and found 500 errors in the logs of the backend service.

## What steps did we perform to identify/detect outages?

To find the real cause of this outage:

- We started checking the logs of microservices for which we got alerts.
- From our microservice(reviews), we found a 5XX error code for downstream API calls.
- From our microservice(reviews), service logs it shows it is not able to reach downstream API which actually causing this issue.

### Possible causes:

1. Network issue caused by AWS VPC resource.
    - First we checked instance on which reviews service was deployed.
    - We check that instance in which subnet and which security group is attached.
    - Then we checked security group outbound rule are allowing this traffic or blocking it.
    - Then we checked subnet routes for NAT gateway is attached or not.
    - After that we checked for NACL rules inbound and outbound.
From above we found that no AWS VPC or Network level misconfiguration are causing this issue.

2. Service outage at downstream API/platform

    For further, The platform team tried to perform a DRY run of the same 3rd API.

    - Platform team logged inside the reviews application pod/container.
    - Performed DNS check on that third party API e.g. `dig api.example.com`
    - After that performed netcat to check the API network connection is reachable or not e.g. `nc -v api.example.com 80`. It was fine.
    - At last performed cURL operation from the reviews application pod and it got failed.


When we faced it first time, there was no alert on the Prometheus or Alertmanager, because it was not configured to detect this kind of failure. Prometheus and Alertmanager are configured to identify and detect Node failure, Pod failure, storage, CPU, and Memory usage issues.

## How we solved it?

As soon as the platform engineering team found that downstream 3rd party APIs of the backend service were down and not serving properly. Implemented error/service unavailable page to identify downstream API outage and serve proper error page to the application users. 
Considering the SLA of downstream 3rd party API, we reported an outage and initiated a conversation with the 3rd party API support team.

## How it can be detected early?

1. Platform engineering team implemented a few metrics checks on service mesh, and configured custom alert rules to identify application service level issues.
2. Also, enabled application log level filtering and rules configured to get alerts based on the logs of the application.
