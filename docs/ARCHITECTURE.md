# Architecture

This repository demonstrates how GitHub Advanced Security and Microsoft Defender for Cloud work together from source code scanning through AKS admission control.

The approved design is the source of truth: [GHAS + Defender for Cloud Demo — Design](superpowers/specs/2026-06-01-ghas-defender-demo-design.md).

Diagrams added in Plan 8.

## Component Map

| Component | Path | Azure target | Owning plan |
| --- | --- | --- | --- |
| Frontend | `src/frontend/` | Azure Static Web Apps | Plan 3 and Plan 5 |
| Backend | `src/backend/` | AKS | Plan 2 and Plan 5 |
| Infrastructure | `infra/` | Azure subscription and resource group | Plan 4 |
| CI/CD | `.github/workflows/` | GitHub Actions | Plan 6 |
| Seeded vulnerabilities | `scripts/seed-vulnerabilities.md` and demo branches | GHAS and Defender controls | Plan 7 |
| Demo guide | `docs/DEMO.md` | Operator documentation | Plan 8 |
