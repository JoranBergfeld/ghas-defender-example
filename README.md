# GHAS + Microsoft Defender for Cloud Demo

[![Implementation](https://img.shields.io/badge/implementation-in%20progress-yellow)](#implementation-status)
[![Security](https://img.shields.io/badge/GHAS%20%2B%20Defender-demo-blue)](docs/superpowers/specs/2026-06-01-ghas-defender-demo-design.md)

This repository contains a self-contained demonstration of how GitHub Advanced Security (GHAS) and Microsoft Defender for Cloud work together from source code to AKS runtime admission control.

The approved design is the source of truth: [GHAS + Defender for Cloud Demo — Design](docs/superpowers/specs/2026-06-01-ghas-defender-demo-design.md).

Implementation in progress — see `docs/superpowers/plans/`.

## Implementation Status

| Area | Status | Owning plan |
| --- | --- | --- |
| Repository foundation | In progress | Plan 1 |
| Java backend | Planned | Plan 2 |
| React frontend | Planned | Plan 3 |
| Azure infrastructure | Planned | Plan 4 |
| azd deployment integration | Planned | Plan 5 |
| GitHub Actions and CodeQL | Planned | Plan 6 |
| Seeded vulnerable branch | Planned | Plan 7 |
| Demo guide and diagrams | Planned | Plan 8 |

## What This Demo Proves

The final demo will show four moments:

1. Secret scanning push protection blocks a fake token before it reaches the remote repository.
2. CodeQL blocks a SQL injection pull request before it can merge into the secure branch.
3. Defender for Containers scans a vulnerable image in ACR and AKS admission control denies the deployment.
4. Defender for Cloud correlates GHAS findings with the running AKS workload.

## Architecture

The target architecture uses:

- React 18 + TypeScript + Vite on Azure Static Web Apps.
- Spring Boot 3.3.x with Java 21 on AKS.
- Azure Database for PostgreSQL Flexible Server on private networking.
- Azure Container Registry Premium with private endpoint.
- Azure Key Vault with RBAC authorization.
- GitHub Actions with OpenID Connect federated credentials.
- Defender for Cloud plans for CSPM, Containers, Key Vault, Open-Source Relational Databases, and Resource Manager.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the architecture reference as it is expanded.

## Prerequisites

The completed demo will require:

- Azure subscription with Owner permissions for subscription-scoped Defender plan enablement.
- Azure Developer CLI (`azd`) 1.10 or newer.
- Azure CLI.
- GitHub CLI (`gh`).
- `kubectl`.
- Docker.
- Java 21.
- Node.js 20.

## Bootstrap Preview

The full bootstrap flow will be completed by later plans. The intended sequence is:

```bash
az login
azd auth login
azd env new demo
azd env set AZURE_LOCATION westeurope
azd up
```

After infrastructure exists, a human completes the Defender for Cloud GitHub connector OAuth consent in the Azure portal and runs the repository setup script that later plans will add.

## Demo Branches

| Branch | Purpose |
| --- | --- |
| `main` | Clean development trunk; CI runs but does not deploy. |
| `secure` | Clean happy-path demo branch; deploys successfully. |
| `vulnerable` | Intentionally vulnerable demo branch; security controls block it. |

Do not remove seeded vulnerabilities from `vulnerable`; they are part of the demonstration and will be documented in `scripts/seed-vulnerabilities.md`.

## Cost and Teardown

Concrete SKU costs will be documented when infrastructure is added. The intended teardown command is:

```bash
azd down --purge
```

## Demo Guide

The complete walkthrough will live in `docs/DEMO.md` when Plan 8 is implemented.

## Troubleshooting

Troubleshooting guidance will cover Defender plan propagation, GitHub connector OAuth, PostgreSQL private DNS, AKS ingress IP assignment, and Static Web Apps deployment once those components exist.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
