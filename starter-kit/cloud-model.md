# Cloud Service Model Decision

## Recommended model: PaaS with selective managed services

For KijaniKiosk's early platform, the best fit is **PaaS (Platform as a Service)** rather than pure IaaS or SaaS.

## Why PaaS is the best choice
KijaniKiosk is launching an online platform and needs to move quickly without spending too much time managing servers, patching operating systems, and handling low-level infrastructure.

A PaaS-oriented design allows the team to:
- deploy application code faster
- reduce operational overhead
- scale more easily as usage grows
- focus engineering effort on product features instead of server maintenance

Examples could include:
- managed web app hosting for the application
- managed database service for transactional data
- object storage for static assets and backups

## Why not pure IaaS?
IaaS gives maximum control, but it also creates more work:
- server provisioning
- scaling rules
- more complex monitoring and maintenance

That level of control is useful later, but it is unnecessary overhead for a starter platform unless there are very specific compliance or custom networking needs.

## Why not SaaS?
SaaS means buying a finished software product and using it as-is. KijaniKiosk is building its own platform, so SaaS cannot be the main hosting model for the core application. SaaS may still be used for support functions such as:
- email
- team collaboration
- issue tracking

## Recommended architecture direction
A practical early-stage approach is:
- **PaaS** for the customer-facing application runtime
- **Managed database service** for persistence
- **Object storage** for uploads and backups
- **SaaS tools** for collaboration, CI/CD, and monitoring where useful

## Final justification
PaaS is the strongest choice because it balances:
- speed of delivery
- lower operational burden