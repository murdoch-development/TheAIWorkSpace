# The AI Workspace

A portable, multi-agent development system for teams using **OpenCode + Backlog.md + Zellij**.

One setup, any project. Share it with your team.

---

## Why

### The Problem

AI coding assistants are powerful, but using them well at scale is hard:

- **Context overload** — One agent trying to plan, code, review, and document does everything poorly. Each role needs different instructions, different models, different permissions.
- **No separation of concerns** — Your AI writes code, reviews its own code, and documents it too. That's a conflict of interest.
- **Unreliable workflows** — Every session starts from scratch. No task tracking, no state, no continuity between sessions.
- **One-size-fits-all** — A general-purpose AI prompt doesn't enforce your team's code quality standards.
- **Not shareable** — Your carefully tuned AI setup lives in scattered config files that are hard to hand to a new teammate.

### The Solution

**Specialized agents with defined roles, orchestrated through a task board, running in a structured terminal.**

```
You
 ├── Plan-WS ──────── Task creator (turns requests into structured tasks)
 ├── Build-WS ─────── Build orchestrator (owns To Do → To Review lifecycle)
 │    ├── coder ──────── Implementation (worktree, code, commit)
 │    ├── reviewer ───── Code review (writes VERDICT tag, does NOT move tickets)
 │    ├── scribe ─────── Documentation
 │    ├── explore ────── Codebase analysis
 │    └── researcher ─── External research
 └── Merger-WS ────── Merge orchestrator (walks you through the merge, 6 human gates)
```

Each agent has:
- **Its own prompt** — tuned for its role
- **Its own model** — cheap models for simple tasks, powerful models for complex ones
- **Its own permissions** — the coder can write files; the reviewer can't
- **Its own skills** — coding philosophy, review methodology, planning protocol

They communicate through a **Backlog.md task board**, not by chatting with each other. This means:
- Tasks are self-contained — any agent can pick up where another left off
- Everything is tracked — you can see what was done, when, and why
- The board is the single source of truth — not someone's chat history

### Why This Works

- **One task = one context window = one PR** — Clean, reviewable units of work
- **The reviewer didn't write the code** — Genuine independent review
- **The coder didn't write the docs** — Scribe writes prose, coder writes code
- **Tasks survive sessions** — The board persists. New session, same state.
- **Code quality is enforced** — Agents load "philosophy" skills before writing anything. The 5 Laws of Elegant Defense and the 5 Pillars of Intentional UI are baked in.
- **Anyone on the team can run it** — One command installs everything.

---

## How

### Architecture Overview

```
TheAIWorkSpace/
├── install-deps.ps1        # Step 0: Install all tools (git, node, bun, zellij, ...)
├── setup-repo.ps1          # Step 1: Set up a single repo (scripts, AGENTS.md, backlog)
├── generate-layout.ps1     # Step 2: Generate a zellij layout for any repos
├── setup-workspace.ps1     # Orchestrator: runs all 3, interactive or parameterized
├── package.ps1             # Bundles scripts + ws profile into a shareable zip
└── README.md               # This file
```

The system has three layers:

| Layer | Tool | Role |
|-------|------|------|
| **Terminal** | Zellij | Structured layout with tabs for each agent and repo |
| **Task Board** | Backlog.md | Source of truth for what needs doing and what's done |
| **AI Agents** | OpenCode (ws profile) | Specialized agents that read from and write to the board |

The `ws` profile (at `~/.config/opencode/profiles/ws/`) is shared across all projects. It contains:

- **7 agents** — Plan-WS, Build-WS, coder, reviewer, scribe, explore, researcher
- **6 skills** — engineering-principles, code-philosophy, frontend-philosophy, code-review, plan-protocol, plan-review
- **6 plugins** — background-agents, notify, workspace-plugin, worktree, kdco-primitives
- **3 MCP servers** — context7 (docs lookup), exa (web search), gh_grep (GitHub code search)
- **1 command** — `/review` (delegates to reviewer agent)

You don't need a new profile per project. The `ws` profile is project-agnostic. What changes per project is:
- The **AGENTS.md** file (project-specific context)
- The **Zellij layout** (which repos, what tab names)
- The **Backlog.md board** (project-specific tasks)

---

## Installation

### Prerequisites

The `install-deps.ps1` script handles everything, but if you want to understand what gets installed:

| Tool | Purpose | Why |
|------|---------|-----|
| **Git** | Version control & worktrees | Worktrees give each task an isolated branch |
| **Node.js** | Backlog.md runtime | Backlog.md is a Node CLI |
| **Bun** | OpenCode runtime | OpenCode and OCX are Bun packages |
| **Zellij** | Terminal multiplexer | Structured layouts with named tabs |
| **Backlog.md** | Task management | The board that orchestrates the agents |
| **OCX** | Profile manager | Installs the ws profile and its plugins |
| **OpenCode** | AI coding assistant | The agent runtime |

### Step 0: Install Dependencies

```powershell
# From TheAIWorkSpace directory
.\install-deps.ps1
```

This checks for each tool, installs missing ones, and verifies the installation. Cross-platform (Windows/macOS/Linux). Safe to re-run.

### Step 1: Set Up a Repo

```powershell
.\setup-repo.ps1 -RepoPath "C:\Projects\my-app"
```

This installs into the repo:
- `scripts/` — 7 workflow scripts (check-board, start-task, create-worktree, complete-task, approve-task, merge-task, done-task)
- `SOFTWARE_ENGINEERING_PRINCIPLES.md` — SOLID, DRY, KISS, YAGNI, testing, lint rules
- `backlog/` — Initialized Backlog.md board (configured with 5 columns)
- `backlog/docs/task-templates.md` — Feature/Bug/Refactor/Docs task templates
- `.gitignore` entry for `backlog/worktrees/`

Note: This does NOT create or modify `AGENTS.md`. That file is repo-specific and owned by the project.

### Step 2: Generate a Layout

```powershell
.\generate-layout.ps1 -LayoutName "my-app-dev" -Repos @("C:\Projects\my-app")
```

This creates a Zellij layout at `~/.config/zellij/layouts/my-app-dev.kdl` with:
- **Plan** tab — Plan-WS agent
- **Build N** tab(s) — Build-WS agent per repo (indexed: Build 1, Build 2, ...)
- **Board N** tab(s) — Backlog.md board view per repo (indexed: Board 1, Board 2, ...)
- **Merge** tab — Merger-WS agent (merge orchestrator)
- **Shell** tab — shell for running servers/builds

Pane commands are emitted as `cmd /c ...` on Windows and as direct invocations on macOS/Linux.

### All at Once

```powershell
# Interactive (prompts for everything)
.\setup-workspace.ps1

# Or fully parameterized
.\setup-workspace.ps1 -ProjectName "My App" `
    -Repos @("C:\Projects\my-backend", "C:\Projects\my-frontend") `
    -Force
```

---

## Daily Workflow

### Launching

```bash
zellij --layout my-app-dev
```

This opens your terminal with all tabs pre-configured. Each agent tab is running OpenCode with the `ws` profile.

### Creating Tasks

Go to the **Plan** tab:

```
/agent Plan-WS
> Add JWT authentication with refresh tokens
```

Plan-WS will:
1. Search the board for duplicates
2. Create a structured task with acceptance criteria
3. Place it on the board in "To Do"

### Building

Go to the **Build** tab:

```
/agent Build-WS
> Process the board
```

Build-WS will:
1. Check the board for "To Do" tasks
2. For each task: start it, spawn the **coder** with task details
3. The coder creates a git worktree, implements, commits, moves to "To Review"
4. Build-WS then spawns the **reviewer** for "To Review" tasks
5. The reviewer checks the code, writes a review, approves or rejects
6. Build-WS reports the outcome

### Reviewing

Use the `/review` command in any OpenCode tab:

```
/review recent
```

This delegates to the reviewer agent, which:
- Loads the code-review skill
- Applies 4 review layers (Correctness, Security, Performance, Style)
- Classifies findings by severity
- Includes positive observations
- Checks philosophy compliance

### Merging

Once a task is in "To Merge", go to the **Merge** tab:

```
/agent Merger-WS
> Merge task-001
```

Merger-WS will:
1. Read the worktree path, branch, and merge target from the ticket
2. Show per-file diffs with explanations and concern flags
3. Pause for your approval (diff review gate + merge strategy choice)
4. Run the merge via `merge-task.ps1`
5. Pause if conflicts occur (you resolve manually)
6. Run tests if available (pause on failure)
7. Run `done-task.ps1` (removes worktree, deletes branch, moves to Done)
8. Pause for push confirmation
9. Print final summary

### Board Columns

```
To Do → In Progress → To Review → To Merge → Done
  |         |            |           |          |
  Plan-WS   Build-WS     reviewer    Merger-WS  done-task.ps1
            + coder       (writes     (merge +
                           VERDICT)    cleanup)
```

---

## Agent Reference

### Plan-WS (Task Creator)

| Aspect | Value |
|--------|-------|
| Role | Translate user requests into structured Backlog.md tasks |
| Model | Powerful (high reasoning) |
| Can write code? | No |
| Can run bash? | Only `backlog` CLI |
| Permission | Read-only + backlog commands |

**When to use:** When you have a feature idea, bug report, or refactor request and want it captured as a proper task on the board.

### Build-WS (Build Orchestrator)

| Aspect | Value |
|--------|-------|
| Role | Owns the full task lifecycle — delegates to coder and reviewer |
| Model | Powerful (medium reasoning) |
| Can write code? | No — delegates |
| Can run bash? | Workflow scripts + backlog CLI |
| Permission | Scripts + backlog + task delegation |

**When to use:** When you want to process the board — pick up To Do tasks and get them implemented.

### Coder (Implementation)

| Aspect | Value |
|--------|-------|
| Role | Implement tasks in isolated git worktrees |
| Model | Fast (high reasoning, low verbosity) |
| Can write code? | Yes — full read/write/edit |
| Can run bash? | Yes — builds, tests, lint |
| Skills | code-philosophy, frontend-philosophy |

**Key rule:** Coder NEVER commits directly to main. It works in a worktree, commits to a task branch, and moves the task to "To Review".

### Reviewer (Code Review)

| Aspect | Value |
|--------|-------|
| Role | Independent code review |
| Model | Fast (high reasoning, medium verbosity) |
| Can write code? | No — read only |
| Can run bash? | git diff/log/show + rg |
| Skills | code-review, code-philosophy, frontend-philosophy |

**Key rule:** Reviewer didn't write the code. It provides genuine independent review with severity classification and philosophy compliance checks.

### Scribe (Documentation)

| Aspect | Value |
|--------|-------|
| Role | Write human-facing content — docs, commit messages, PR descriptions |
| Model | Fast (high verbosity) |
| Can write code? | No — only markdown/docs |
| Can run bash? | No |

**When to use:** When you need documentation, changelogs, or polished prose about code.

### Explore (Codebase Analysis)

| Aspect | Value |
|--------|-------|
| Role | Read-only codebase exploration |
| Model | Fast (low reasoning) |
| Can write code? | No |
| Can run bash? | Read-only commands (ls, cat, grep, git log, etc.) |

**When to use:** When you need to understand how something works without modifying anything.

### Researcher (External Research)

| Aspect | Value |
|--------|-------|
| Role | Search external sources — docs, GitHub, web |
| Model | Fast (high reasoning) |
| Can write code? | No |
| Can run bash? | Read-only (gh, npm info, dig, etc.) |
| Tools | context7, exa, gh_grep, webfetch |

**When to use:** When you need to research a library, API, or pattern from external sources.

---

## Skills Reference

### code-philosophy (The 5 Laws of Elegant Defense)

Loaded by coder and reviewer alongside engineering-principles for all backend/logic work:

1. **Early Exit** — Guard clauses at the top, not nested ifs
2. **Parse Don't Validate** — Parse at boundaries, trust internally
3. **Atomic Predictability** — Pure functions, same input = same output
4. **Fail Fast, Fail Loud** — Invalid states halt immediately with descriptive errors
5. **Intentional Naming** — Code reads like an English sentence

### engineering-principles (Software Engineering Principles)

**Always loaded by coder and reviewer before any code work.** Covers:

- **SOLID** — Single Responsibility, Open/Closed, Liskov, Interface Segregation, Dependency Inversion
- **Design Principles** — DRY, KISS, YAGNI, Separation of Concerns, Composition over Inheritance, Encapsulation, Orthogonality, Reversibility, Boy Scout Rule, Least Privilege, Single Source of Truth, Convention over Configuration, Defensive Programming
- **Anti-patterns** — No `any`, no premature abstraction, no God objects, no circular deps, no deep nesting, no flag args, no magic strings, no scattered conditionals
- **Code Organization** — One concern per file, imports at top, no magic numbers, actionable error messages, comments explain why
- **Testing** — Tests as documentation, fast/isolated/deterministic, test behavior not implementation, test the edges
- **Lint Rules** — ESLint thresholds that enforce the principles

Also installed as `SOFTWARE_ENGINEERING_PRINCIPLES.md` in each repo by `setup-repo.ps1`.

### frontend-philosophy (The 5 Pillars of Intentional UI)

Loaded by coder and reviewer before any frontend work:

1. **Typography with Character** — No generic fonts (Inter, Roboto, Arial)
2. **Committed Color & Theme** — Bold palettes, not timid gradients
3. **Purposeful Motion** — One great animation beats a dozen small ones
4. **Brave Spatial Composition** — Asymmetry, overlap, grid-breaking
5. **Atmosphere & Depth** — Gradients, textures, shadows, layering

### code-review

Loaded by reviewer for systematic review across 4 layers:
- Correctness, Security, Performance, Style
- Severity: Critical, Major, Minor, Nitpick
- Only reports findings with >=80% confidence

### plan-protocol

Loaded when creating implementation plans:
- YAML frontmatter with status, phase, updated date
- Phases with status markers
- Citations for research-based decisions

### plan-review

Loaded when reviewing plans (not code):
- Checks citation quality, completeness, actionability
- Verifies goals are specific and measurable

---

## Workflow Scripts

Installed by `setup-repo.ps1` into each repo's `scripts/` directory:

| Script | What it does | Status guard | Called by |
|--------|-------------|-------------|-----------|
| `check-board.ps1` | Lists tasks by status (or all) | — | Any agent |
| `start-task.ps1` | Moves task to "In Progress" | Must be "To Do" | Build-WS |
| `create-worktree.ps1` | Creates worktree + writes ref to ticket | — | Coder |
| `complete-task.ps1` | Moves to "To Review" | Must be "In Progress" | Coder |
| `approve-task.ps1` | Moves to "To Merge" | Must be "To Review" | Build-WS (after reviewer APPROVED) |
| `merge-task.ps1` | Performs the git merge (no-ff/squash) | — | Merger-WS |
| `done-task.ps1` | Moves to "Done" + removes worktree + deletes branch | Must be "To Merge" | Merger-WS |

**Never edit Backlog.md markdown files directly.** Always use the `backlog` CLI or these scripts.

### Machine-Readable Ticket Fields

Scripts and agents use structured tags in ticket descriptions for deterministic communication:

- `<!-- WORKTREE_START -->` / `<!-- WORKTREE_END -->` — worktree path, branch, merge target. Written by `create-worktree.ps1`.
- `<!-- VERDICT: APPROVED -->` or `<!-- VERDICT: REJECTED -->` — written by reviewer, read by Build-WS.

---

## Customization

### Changing Models

Edit `~/.config/opencode/profiles/ws/opencode.jsonc`:

```jsonc
"model": "openrouter/your-preferred-model",
"small_model": "openrouter/your-cheaper-model",
```

Per-agent overrides:

```jsonc
"agent": {
    "coder": {
        "model": "openrouter/a-faster-model",
        "temperature": 0.2
    }
}
```

### Adding MCP Servers

```jsonc
"mcp": {
    "your-server": {
        "type": "remote",
        "url": "https://your-mcp-server.com/mcp",
        "enabled": true
    }
}
```

### Project-Specific Context

Edit `AGENTS.md` in each repo to add:
- Current project state
- Critical technical context (pinned versions, gotchas)
- Developer commands (build, test, lint)
- Architecture quirks
- Spec file references

This is what agents read first when they start working on your project.

---

## Sharing With Your Team

1. **Put `TheAIWorkSpace/` somewhere accessible** — internal repo, shared drive, or USB
2. **Team member runs:**

   ```powershell
   cd TheAIWorkSpace
   .\setup-workspace.ps1
   ```

3. **They follow the prompts** — enters their project name and repo paths
4. **Done** — they have the full multi-agent setup

The only thing they need to configure personally is API keys in their OpenCode config.

---

## Troubleshooting

### "backlog: command not found"
```bash
npm install -g backlog.md
```

### "zellij: command not found"
See: https://zellij.dev/documentation/installation

### OpenCode can't find the profile
Check that the config exists at:
- Windows: `~/.config/opencode/profiles/ws/opencode.jsonc`
- macOS/Linux: `$XDG_CONFIG_HOME/opencode/profiles/ws/opencode.jsonc`

### Scripts can't run (Windows execution policy)
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Zellij layout has wrong paths
Re-run:
```powershell
.\generate-layout.ps1 -LayoutName "your-layout" -Repos @("path/to/repo") -Force
```

### Bun not found after install (Windows)
Restart your terminal. Bun adds itself to PATH, but the current session won't see it.

---

## File Locations

| What | Windows | macOS / Linux |
|------|---------|---------------|
| OpenCode config | `~/.config/opencode/` | `$XDG_CONFIG_HOME/opencode/` |
| ws profile | `~/.config/opencode/profiles/ws/` | same |
| Zellij layouts | `%APPDATA%\Zellij\config\layouts\` | `~/.config/zellij/layouts/` |
| Backlog.md board | `<repo>/backlog/` | same |
| Workflow scripts | `<repo>/scripts/` | same |
| Git worktrees | `<repo>/backlog/worktrees/` | same |

---

## Philosophy

This setup is built on a few core beliefs:

1. **Specialization beats generalization** — An agent that only writes code writes better code than one that also plans, reviews, and documents.
2. **The board is the truth** — Not chat history, not someone's memory. The task board is what happened and what needs to happen.
3. **One task, one context, one PR** — Small, focused units of work are easier to review, easier to merge, and easier to undo.
4. **Quality is not optional** — The philosophy skills aren't suggestions. They're loaded before any code is written.
5. **Shareable by default** — Your team shouldn't need a 20-page onboarding doc to use your AI setup. One command.

---

*Internal tooling — adapt as needed for your team.*
