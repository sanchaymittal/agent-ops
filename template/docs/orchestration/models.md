# Model bindings — single source of truth

Read when: resolving which model fills a slot, or swapping a model.

Every other doc names slots (COORDINATOR, PLANNER, CODER, REVIEWER), never models. To swap a model, edit this table — nothing else changes, no re-init.

| Slot | Model | Duty |
| --- | --- | --- |
| COORDINATOR | {{COORDINATOR}} | Orchestrates: plans, dispatches, verifies, commits, updates tracker. Must have tracker access when an external tracker is configured. |
| PLANNER | {{PLANNER}} | Advisor: architecture, gates, tie-breaks, on-demand escalation consults ([escalation.md](./escalation.md)). Not in the hot path; never misc work. |
| CODER | {{CODER}} | Labor: default implementation, with project roles. |
| REVIEWER | {{REVIEWER}} | Review: `engineering-code-reviewer` role. |
| MISC | any cheap/free model | Throwaway/cheap tasks. Never the PLANNER model. |

Rules (hold regardless of which models are bound):

- Any CLI that reads `AGENTS.md` (claude/fable, codex, agy, opencode, hermes, …) can fill any slot; protocol and role files are model-independent.
- Cross-model review: the model that authored a change never reviews it (CODER writes → REVIEWER reviews; REVIEWER writes → CODER or PLANNER reviews). CODER and REVIEWER bindings must differ.
