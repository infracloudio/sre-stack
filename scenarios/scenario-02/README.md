# Scenario: Increased DB connection count

## Description:

A ecommerce application [instana/robot-shop](https://github.com/instana/robot-shop) hosted on Managed kubernetes cluster which stores all the user related important data in MySQL server, which is shared with some other operational and analytical microservices as well. 

One day, Robot-shop started facing high page load time and at the same time Shipping service was unable to fetch data from the MySQL server, Causing the system to have severely degraded performance.

### Diagram

![robot-shop-mysql-conn-outage](https://github.com/infracloudio/sre-stack/assets/581287/a5221a2c-ce91-4e6b-b2a3-b606333ab43c)





## What steps did we perform to identify/detect outages?

To find the real cause of this outage:
- High API latencies were noticed from shipping service
- We started checking logs of application.
- Checked status of microservices in Kiali dashboard for Istio-service-mesh.
- We checked on MySQL DB connection metrics
- Debugged MySQL connections by logging into RDS

### Possible causes:

1. Other shared application are using high amount of db connections.
    - First we checked Database connection on the application.

2. Bug in application which open connection and leave.
    - We checked open connection via SQL query.
    `show status where `variable_name` = 'Threads_connected';`


