# Worker supervision

Read when: spawning, supervising, or recovering a delegated worker.

## Spawn

- Run `.orchestration/preflight.sh` and acquire the writer lease before a writing worker starts.
- Use the narrowest capability profile and a bounded dispatch message.
- Parallel writers use separate worktrees. Never nest one orchestrator inside another.

## Wait

- Prefer a completion event that wakes the coordinator outside the model loop.
- Otherwise use one non-consuming blocking wait for all workers, with a window of at least 15 minutes.
- Never poll status or read per-worker terminals. Budget at most two supervision calls per dispatched task.
- `.orchestration/burn.py` measures polling cost from local session logs.

## Finish or recover

- The worker never commits. The coordinator inspects the diff, runs the checks, and releases the lease.
- On a blocked gate, stop until the recorded gate opens; never ask a worker to guess.
- On a decision block or two failed verification rounds, stop and ask the user.
- On a hang, preserve terminal output and the diff, terminate the worker, release the lease, and restart from the same task in a fresh worktree.
