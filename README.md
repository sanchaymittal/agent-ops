# Agent Ops Template

Install the lightweight agent operating contract and optional delegation safeguards into a repository:

```bash
./init.sh TARGET_DIR PROJECT_NAME [VERIFY_CMD]
```

Example:

```bash
./init.sh ~/github/example-app example-app 'npm run verify'
```

The installer adds `AGENTS.md`, a `CLAUDE.md` symlink, concern-indexed docs, and `.orchestration/`. Direct work is the default. The orchestration directory is used only when the user explicitly requests worker delegation or parallel work.

Included safeguards:

- `preflight.sh` checks the repository, base SHA, verify command, optional CLI, and lease.
- `lease.sh` provides an atomic one-writer guard for a shared worktree.
- `burn.py` diagnoses polling and supervision cost from local Codex and Claude session logs.

Generic role personas, model bindings, prompt/report ceremonies, and runtime supervisors are intentionally not installed. Use the built-in roles and native workflow of the agent CLI when specialization is useful.

For an existing installation:

```bash
./init.sh --check TARGET_DIR
./init.sh --upgrade TARGET_DIR
```

Upgrade preserves locally modified managed files and reports obsolete files for human review. It does not delete them automatically.

Run the template checks with:

```bash
./verify.sh
```
