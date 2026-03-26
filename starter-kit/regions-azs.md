# Region and Availability Zone Reasoning

## Region selection
KijaniKiosk should choose a cloud **region geographically close to its main users** to reduce latency and improve user experience.

If the main users are in Kenya or East Africa, the team should prefer the closest supported cloud region that offers:
- low network latency
- multiple availability zones
- managed database and networking services
- room for future scaling and disaster recovery

If an East Africa region is not available for the chosen provider, the next best option is a nearby region with strong service coverage and at least two availability zones.

## Why region choice matters
The region affects:
- application response time
- data residency considerations
- service availability
- disaster recovery options
- operational cost

A random region choice would be poor engineering. The selected region should match the customer base and service requirements.

## Multi-Availability-Zone design
The platform should be designed across **at least two availability zones** inside one region.

Example:
- AZ A hosts one application instance or node
- AZ B hosts another application instance or node
- the load balancer can direct traffic to healthy targets in either zone
- the database should be configured for multi-AZ availability if supported

## Reliability reasoning
Using multiple AZs improves reliability because a failure in one data center area does not take down the whole application.

Benefits:
- higher availability
- protection against a single-AZ outage
- safer maintenance windows
- better resilience during infrastructure failures

## Suggested early architecture
- One region for the primary environment
- Two AZs for redundancy
- Public entry through a load balancer
- Private application and data components distributed for resilience where possible
