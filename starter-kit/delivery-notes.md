# DevOps Delivery Notes

## Purpose
This starter kit documents the engineering foundations KijaniKiosk should agree on before launching the platform. The goal is not to build a full production environment yet, but to show sound DevOps reasoning early.

## How Flow appears in this workflow
Flow is about moving work smoothly from idea to delivery with minimal handoff friction.

- I used a simple branching model: `main` for stable work, `develop` for integration, and `feature/starter-kit-files` for the assignment work.
- The feature branch keeps documentation and architecture changes isolated until they are reviewed.
- A pull request from `feature/starter-kit-files` to `develop` creates a clean path for integrating changes.
- Small, focused commits make it easier to understand what changed and reduce merge risk.

## How Feedback appears in this workflow
Feedback is about finding issues early rather than after release.

- The pull request serves as the main feedback checkpoint.
- The PR description explains what was added, why it was added, and what reviewers should inspect.
- The network design and IAM policy are written in plain language so a teammate can challenge risky assumptions quickly.
- By documenting routing logic and least privilege choices, the team can catch security and reliability mistakes before deployment.

## How Learning appears in this workflow
Learning is about improving the system and the team after every change.

- Each file explains not only the decision made, but also the reason behind it.
- The reflection questions at the end of the project encourage continuous improvement.
- The team can reuse this starter kit as a baseline for future services instead of redesigning foundational decisions from scratch.
- Recording early decisions helps new team members understand the architecture .

## Delivery workflow used
1. Create repository: `kijaniosk-devops-foundation`
2. Create `main` branch
3. Create `develop` branch
4. Create `feature/starter-kit-files`
5. Add the starter-kit documentation and network diagram
6. Open a pull request from `feature/starter-kit-files` into `develop`
7. Review and merge the PR
8. Keep `main` reserved for stable, approved work
