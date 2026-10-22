## Board-Driven Workflow

This workspace uses a **board-driven workflow** with Backlog.md. Tasks move through 5 columns:

```
To Do -> In Progress -> To Review -> To Merge -> Done
```

### Workflow Scripts

All scripts are in `scripts/` and must be used (never manually edit task files):

| Script | Purpose |
|---|---|
| `scripts/check-board.ps1` | List tasks by status. Usage: `pwsh ./scripts/check-board.ps1 "To Do"` |
| `scripts/start-task.ps1` | Move task to In Progress (guard: must be "To Do") |
| `scripts/create-worktree.ps1` | Create a git worktree for a task + write worktree ref to ticket |
| `scripts/complete-task.ps1` | Move task to To Review (guard: must be "In Progress") |
| `scripts/approve-task.ps1` | Move task to To Merge (guard: must be "To Review") |
| `scripts/reject-task.ps1` | Move task back to In Progress (guard: must be "To Review") |
| `scripts/read-verdict.ps1` | Deterministically parse VERDICT tag (exit: 0=approved, 1=rejected, 2=not found) |
| `scripts/write-verdict.ps1` | Write VERDICT tag with self-verification (exit: 0=confirmed, 1=failed) — used by reviewer |
| `scripts/merge-task.ps1` | Perform the actual git merge (exit: 0=success, 1=conflicts, 2=error) |
| `scripts/done-task.ps1` | Move task to Done + remove worktree + delete branch (guard: must be "To Merge") |

### Agent Roles

| Agent | Role | Board Permissions |
|---|---|---|
| **Plan-WS** | Takes user requests -> creates tasks on the board | Create, Edit, Read |
| **Build-WS** | Creates worktree -> delegates to coder -> spawns reviewer -> reads VERDICT via script -> moves tickets | Move only, Read |
| **coder** | Implements in pre-created worktree -> commits -> moves to To Review | Edit (append), Read |
| **reviewer** | Reads worktree ref -> reviews code -> writes VERDICT tag via `write-verdict.ps1` | Read, Skill, Edit (via script only) — does NOT move tickets |
| **Merger-WS** | Walks developer through merge process with diff review, human decision gates, git merge, cleanup | Move (To Merge -> Done), Read |
| **scribe** | Writes documentation when delegated | Read only |
| **explore** | Reads codebase when delegated | Read only |
| **researcher** | Searches docs/web when delegated | Read only |

### Machine-Readable Ticket Fields

The system uses structured tags in ticket descriptions for deterministic agent communication:

- `<!-- WORKTREE_START -->` / `<!-- WORKTREE_END -->` — contains worktree path, branch, and merge target. Written by `create-worktree.ps1` at creation time.
- `<!-- VERDICT: APPROVED -->` or `<!-- VERDICT: REJECTED -->` — written by the reviewer. Build-WS reads this tag to decide the next action.

### Flow Example

```
User: "Fix CFuel null pointer"
  -> Plan-WS creates task-001 "Fix null dereference in CFuel::update"
  -> Build-WS runs start-task.ps1 task-001 (-> In Progress)
  -> Build-WS runs create-worktree.ps1 task-001 (creates backlog/worktrees/task-001, writes worktree ref to ticket)
  -> Build-WS spawns coder with task details (worktree guaranteed ready)
  -> coder implements in worktree, commits
  -> coder runs complete-task.ps1 task-001 (-> To Review)
  -> Build-WS spawns reviewer with task ID
  -> reviewer reads worktree ref from ticket, reviews code, writes <!-- VERDICT: APPROVED --> via write-verdict.ps1
  -> reviewer does NOT move the ticket — reports back to Build-WS
  -> Build-WS runs read-verdict.ps1 task-001 (exit 0 = APPROVED)
  -> Build-WS runs approve-task.ps1 task-001 (-> To Merge)
  [if REJECTED: Build-WS runs reject-task.ps1 task-001 (-> In Progress), re-spawns coder]
  -> Developer invokes Merger-WS from the Merge N tab for that repo with task-001
  -> Merger-WS reads worktree path, branch, and merge target from ticket
  -> Merger-WS shows diffs with explanations and concern flags
  -> PAUSE: developer reviews diffs, chooses merge strategy (no-ff/squash)
  -> Merger-WS runs merge-task.ps1 task-001 -Strategy no-ff
  -> PAUSE: if conflicts, developer resolves manually
  -> Merger-WS runs tests (if available)
  -> PAUSE: if tests fail, developer decides (rollback/keep)
  -> Merger-WS runs done-task.ps1 task-001 (removes worktree, deletes branch, -> Done)
  -> Merger-WS tells developer to push manually (git push origin <target-branch>)
  -> Merger-WS prints final summary
```

---

## Backlog.md Workflow

**For every user request in this project, run `backlog instructions overview` before answering or taking action.**

Use the overview to decide whether to search, read, create, or update Backlog tasks.

Before task lifecycle actions, read the matching detailed guide:
- `backlog instructions task-creation` before creating or splitting tasks
- `backlog instructions task-execution` before planning, changing status or assignee, adding a plan or implementation notes, or implementing task work
- `backlog instructions task-finalization` before checking acceptance criteria, writing final summaries, or moving tasks to terminal statuses

Use `backlog <command> --help` before running unfamiliar commands. Help shows options, fields, and examples.

Do not edit Backlog task, draft, document, decision, or milestone markdown files directly. Use the `backlog` CLI so metadata, relationships, and history stay consistent.
