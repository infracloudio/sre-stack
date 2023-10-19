# Scenario: Increased DB connection count

## Description:

A ecommerce application hosted on Managed kubernetes cluster which stores all the user related important data in MySQL server, which is shared with some other operational and analytical microservices as well. 

One day, ecommerce application started facing high page load time and some time backend microservices where unable to fetch data from the MySQL server.

### Diagram

![Application](https://github.com/infracloudio/sre-stack/blob/main/etc/image/scenario-2-application-arch.png?raw=true)


## What steps did we perform to identify/detect outages?

To find the real cause of this outage:

- We started checking logs of application.
- Checked status of microservices in dashboard.

### Possible causes:

1. Other shared application are using high amount of db connections.
    - First we checked Database connection on the application.

2. Bug in application which open connection and leave.
    - We checked open connection via SQL query.
    `show status where `variable_name` = 'Threads_connected';`

