# Scenario: Downstream API/Application performance degradation

## Description:

In a three-tier application that consists of web frontend, backend, and some third-party APIs. One fine day, the backend service started facing some issues while making some HTTP GET/POST calls on 3rd party API. Due to this frontend was unable to load that part of the application from the backend service. These lead to cascading failure due to an outage at 3rd party API platform.

### Diagram

![Application](https://github.com/infracloudio/sre-stack/blob/main/etc/image/scenario-1-application-arch.png?raw=true)

## How do we detect outages?

This was detected via the QA/NOC team when they were doing regular testing of the product and platform. They started facing this issue on the Application web UI and then reported it to the platform engineering team.

The Platform engineering team started checking on Monitoring dashboards and found 500 errors in the logs of the backend service.

## What steps did we perform to identify/detect outages?

First, there was no alert on the Prometheus or Alertmanager, because it was not configured to detect this kind of failure. Prometheus and Alertmanager are configured to identify and detect Node failure, Pod failure, storage, CPU, and Memory usage issues.

To find the real cause of this outage:
We started checking the logs of each and every microservices.
From the backend, we found a 5XX error code for downstream API calls.
From the backend service logs it shows which downstream API is actually causing this issue.
The platform team tried to perform a DRY run of the same 3rd API and found it was down.

## How we solved it?

As soon as the platform engineering team found that downstream 3rd party APIs of the backend service were down and not serving properly. Implemented error/service unavailable page to identify downstream API outage and serve proper error page to the application users. 
Considering the SLA of downstream 3rd party API, we reported an outage and initiated a conversation with the 3rd party API support team.

## How it can be detected early?

Platform engineering team implemented a few metrics checks on service mesh, and configured custom alert rules to identify application service level issues. 
Also, enabled application log level filtering and rules configured to get alerts based on the logs of the application.
