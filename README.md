# monogatari-kit

A **collaborative authoring platform for branching interactive video stories** (visual novels).

Author writes an outline → grows a DAG of branches → fills in chapter text → produces a storyboard. AI assists drafting throughout. Characters are first-class entities with AI-generated outfit variants. Output eventually feeds a video pipeline targeting Steam.

## Status

- **Stage:** M1 in progress — local k8s baseline
- **Done:** M0 scaffold, PRD locked (v3, 2026-05-04)
- **Up next:** M2 Helm chart skeleton + BetterAuth login page

## Tech stack (locked — see [PRD §6](./docs/PRD.md#6-tech-stack-locked))

Next.js · tRPC · Drizzle · Postgres (CNPG) · BetterAuth · BullMQ · Redis · MinIO · Tailwind · TanStack Query · Zustand · xyflow · Vercel AI SDK · OpenRouter · Gemini Flash Image

**Hosting:** Kubernetes (Helm chart) — **Level B strict self-host**. No managed runtime services. GKE allowed as k8s control plane only (M7).

## Milestones

| # | Milestone | Status |
|---|-----------|--------|
| 0 | Scaffold + PRD | ✅ Done |
| 1 | Local k8s baseline (CNPG + Redis + MinIO) | 🚧 In progress |
| 2 | Helm chart skeleton + auth | |
| 3 | Project + collab + recycle bin | |
| 4 | Story tree + chapter editor + soft-lock | |
| 5 | Storyboard + character + image queue | |
| 6 | Prompt mgmt + OpenRouter streaming | |
| 7 | GKE deploy + ingress + TLS | |

Full milestone definitions in [PRD §9](./docs/PRD.md#9-process--learning-plan).

## Documents

- [`docs/PRD.md`](./docs/PRD.md) — Product requirements, ERD, tech stack, milestones, learning plan
- [`docs/stack-reference.md`](./docs/stack-reference.md) — Fullstack TS slot reference
- [`infra/k8s/README.md`](./infra/k8s/README.md) — Local k8s manifests + apply order
- [`notes/`](./notes/) — Build journey, milestone by milestone (FDE training log)
- [`CLAUDE.md`](./CLAUDE.md) — Context for AI-assisted dev sessions

## FDE training framing

This repo doubles as a **Forward Deployed Engineer training ground**: the strict self-host Level B policy means hands-on with Postgres ops, Redis, k8s networking, TLS, auth — none of it abstracted by managed services. The product is real and worth shipping, but the FDE muscles are the side-quest worth its own log.

See [`notes/`](./notes/) for the chronological build journey, including the operator install race condition, CRD vocabulary, StatefulSet ordinal surprises, and other things you only learn by running into them.

## License

MIT
