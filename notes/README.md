# Build notes

Chronological build log for monogatari-kit, milestone by milestone. Each note captures:

- **What we did** — concrete steps, manifests applied, commands run
- **What we decided** — the trade-offs faced and which way we went, with the *why*
- **What surprised us** — gotchas, errors, race conditions, things that don't appear in tutorials
- **FDE muscle exercised** — which Forward Deployed Engineer skill this round built

The PRD ([`docs/PRD.md`](../docs/PRD.md)) is the spec: what to build. These notes are the journal: what happened while building it.

## Index

| # | Milestone | Note |
|---|-----------|------|
| 1 | Local k8s baseline | [`m1-local-k8s-baseline.md`](./m1-local-k8s-baseline.md) |
| 2 | Helm chart skeleton + auth | (pending) |
| 3 | Project + collab + recycle bin | (pending) |
| 4 | Story tree + chapter editor + soft-lock | (pending) |
| 5 | Storyboard + character + image queue | (pending) |
| 6 | Prompt mgmt + OpenRouter streaming | (pending) |
| 7 | GKE deploy + ingress + TLS | (pending) |

## Related external notes

Some deeper-than-build-log concepts get standalone deep-dives in the Obsidian vault under `Learning/Deep Dives/`. Build notes link out when relevant — e.g. *Kubernetes Vocabulary: CRD, Operator, PVC, StatefulSet* was written during M1.
