# docs/ — concern router

One directory per concern, each with its own ≤40-line `index.md`. Load indexes, not directories.

## Read protocol (all agents)

1. Always load: `AGENTS.md` → this file → [`gates/index.md`](./gates/index.md). Nothing else by default.
2. Task touches a concern → read that concern's `index.md`.
3. Read a leaf doc only when its index entry says it matters for your task.
4. Never bulk-read `docs/`. When editing docs, keep every index ≤ 40 lines and give every leaf doc a one-line `Read when:` header.
5. Stateful data (gate status) lives in indexes; prose detail lives in leaf docs.

## Concerns

| Concern | Index | Contents |
| --- | --- | --- |
| Gates | [`gates/index.md`](./gates/index.md) | Live blocker status table — mandatory pre-work check |
| Orchestration | [`orchestration/index.md`](./orchestration/index.md) | How work gets dispatched: coordinator/worker, orca, issue tracker |
| Product | [`product/index.md`](./product/index.md) | Scope, metrics, product source docs |
| Runbooks | [`runbooks/index.md`](./runbooks/index.md) | Step-by-step owner/agent procedures |
| Engineering | [`engineering/index.md`](./engineering/index.md) | Verify pipeline, test/smoke conventions |
