# Project Context for Claude

Read this at session start. Tight on purpose — details live in `docs/PRD.md`.

---

## What this project is

VN Authoring Platform — collaborative web app for authoring branching video novels. Spinoff from sibling repo `../vn-poc/`. See `docs/PRD.md` for full spec.

## User & goals

User: chiauhung. Data engineer, team senior, transitioning toward **Forward Deployed Engineer** role.

This project serves three goals at once:
1. Replace manual `story.json` editing from vn-poc
2. Learn the modern fullstack TS stack hands-on — every slot exercised (see `docs/stack-reference.md`)
3. **FDE training** — strict self-host policy means user touches Postgres ops, Redis, k8s networking, TLS, auth directly. None of it abstracted away.

## Locked decisions (do NOT propose alternatives)

- **Hosting:** Kubernetes + Helm chart, **Level B strict self-host**. No managed services for runtime (no Cloud SQL, no Memorystore, no GCS bucket SDK, no Clerk). Postgres = CloudNativePG operator; Redis = self-host in cluster; storage = MinIO; auth = BetterAuth in-app library. GKE allowed only as k8s control plane (M7), never managed runtime services.
- **AI:** OpenRouter via Vercel AI SDK for text streaming; Nano Banana via BullMQ queue for image gen
- **DB:** Postgres + Drizzle. App speaks S3-compatible API via `@aws-sdk/client-s3` (endpoint = MinIO locally; swap to S3/GCS via env if ever needed)
- **Auth:** BetterAuth (NOT Clerk). User explicitly rejected vendor auth.
- **Branching model:** DAG (multi-incoming edges allowed); cycles forbidden. State / 数值 / unlock conditions deferred to Phase 2.
- **Local k8s:** Docker Desktop's built-in Kubernetes (not kind, not minikube). User has it.

## Working style preferences

- **Decisions, not syntax** — user no longer codes; explain the "why" and trade-offs, not implementation details. Skip code walkthroughs unless asked.
- **Q&A style** for explanations — answer "why this? what does it solve? what are the cases?" Not point-form feature lists.
- **中英 mix** at insight points — user's native language is Chinese; key terms in 中文 stick.
- Short, tight, no padding. One sentence often beats one paragraph.
- **Never skip GPG signing** on commits — if signing fails, wait for user to fix, don't bypass with `--no-gpg-sign`.
- **Don't pitch managed services** as shortcuts. Level B is locked for learning reasons; suggesting Cloud SQL "to ship faster" defeats the project's purpose.

## Current state

- **PRD version:** v3 (final, locked 2026-05-04) — `docs/PRD.md`
- **Milestone:** M0 done (scaffold + docs). **Next: M1 — local k8s baseline.** Get Docker Desktop k8s up + Postgres (CNPG) + Redis + MinIO running, all accessible via `kubectl exec`.

## Quiz / learning loop

After every milestone, write 4 FDE-style probe questions for the user to attempt:
- **L1** basics (immediate triage path, e.g. "Pod CrashLoopBackOff, first 3 things you check?")
- **L2** isolation (narrow down the problem, e.g. "Postgres slow query — index issue or query plan?")
- **L3** fix (hands-on surgery, e.g. "Helm upgrade left release state corrupt — recover by hand")
- **L4** war story (vague problem, generate hypothesis list, e.g. "User says AI gen sometimes hangs, logs show nothing")

User attempts → review → weak spots trigger rebuild of that piece. Total ~28 questions across 7 milestones. See `docs/PRD.md` §9.

## Sibling repos

- `../vn-poc/` — original POC (Kling + Cloud Run). TypeScript types at `src/engine/types.ts` seed the new platform's data model. **Don't edit vn-poc from this repo.**

## When user opens a fresh session and says "let's start M{N}"

Confirm before building:
1. Is the milestone scope still as-defined in PRD §9?
2. Any open questions in PRD §8 block this milestone?

Then proceed.
