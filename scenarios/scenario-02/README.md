# Scenario: Increased DB connection count

## Description:

A ecommerce application hosted on Managed kubernetes cluster which stores all the user related important data in MySQL server, which is shared with some other operational and analytical microservices as well. 

One day, ecommerce application started facing high page load time and some time backend microservices where unable to fetch data from the MySQL server.

### Diagram

![Application](https://github.com/infracloudio/sre-stack/blob/main/etc/image/scenario-2-application-arch.png?raw=true)
