# VN Authoring Platform

Collaborative authoring platform for branching interactive video stories. Spinoff from sibling `../vn-poc/` — replaces the manual `story.json` editing pain with a real UI, multi-user collab, and AI-assisted authoring.

## Status

- **Stage:** Scaffolding (M0 done — PRD locked, folder + docs created)
- **Next milestone:** M1 — Local k8s baseline (Postgres + Redis + MinIO running on Docker Desktop k8s)

## Documents

- [`docs/PRD.md`](./docs/PRD.md) — Product requirements, ERD, tech stack, milestones, learning plan
- [`docs/stack-reference.md`](./docs/stack-reference.md) — Fullstack TS slot reference (the mental model behind stack picks)
- [`CLAUDE.md`](./CLAUDE.md) — Context for AI-assisted dev sessions

## Tech stack (locked, see [PRD §6](./docs/PRD.md#6-tech-stack-locked))

Next.js · tRPC · Drizzle · Postgres (CNPG) · BetterAuth · BullMQ · Redis · MinIO · Tailwind · TanStack Query · Zustand · xyflow · Vercel AI SDK · OpenRouter · Nano Banana

**Hosting:** Kubernetes (Helm chart) — **Level B strict self-host**. No vendor SaaS for runtime services. GKE allowed as k8s control plane only (M7).

## Why this exists

1. Replaces hand-editing `story.json` from vn-poc
2. Training ground for fullstack TS stack (every slot exercised)
3. Training ground for **Forward Deployed Engineer** skills — strict self-host means hands-on with Postgres, Redis, k8s networking, TLS, auth (none of it abstracted by managed services)

## Dev setup

TBD — filled in during M1.
