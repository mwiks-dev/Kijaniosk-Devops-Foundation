# KijaniKiosk DevOps Foundation

This repository contains Week 1 DevOps starter kit for KijaniKiosk.

## Folder structure

- `starter-kit/delivery-notes.md`
- `starter-kit/cloud-model.md`
- `starter-kit/regions-azs.md`
- `starter-kit/iam-least-privilege.md`
- `starter-kit/network-topology.png`

## Branching strategy
- `main`
- `develop`
- `feature/starter-kit-files`


## Reflection answers
### Where was I tempted to take shortcuts?
I was tempted to write brief generic explanations for IAM and network design, but the rubric rewards reasoning, so I documented the “why” behind each decision.

### Which architectural decision required the most reasoning?
Choosing the cloud model required the most reasoning because I had to balance delivery speed, operational overhead, and future flexibility. PaaS was the best trade-off for an early-stage platform.

### If the platform grows significantly, what should improve first?
The first improvement should be stronger resilience and observability: multi-AZ application deployment, automated CI/CD, centralized logging, monitoring, and a more advanced network design that supports scale securely.