---
name: expand-task-skill
description: >-
  Expand and expound meager Backlog.md tickets into developer-ready
  specifications with full descriptions, testable acceptance criteria, and
  Definition of Done checklists. Use when the user asks to "expand", "expound",
  "flesh out", "prepare for handoff", or "beef up" a task, or when a task lacks
  acceptance criteria or DoD items.
id: doc-1
title: expand-task-skill SKILL.md
type: other
created_date: '2026-08-25 17:26'
tags:
  - backlog
  - task-management
  - workflow
---

# Expand and Expound Task

This skill transforms thin, skeletal Backlog.md tickets into comprehensive, self-contained specifications that a developer can pick up without prior conversation context.

## When to Use

Trigger on requests like:
- "expand task X" / "expound on task X"
- "prepare task X for developer handoff"
- "flesh out task X" / "beef up task X"
- "task X needs more detail before developers can pick it up"
- "task X has no acceptance criteria / no definition of done"

## When NOT to Use

- Creating a brand-new task from scratch (that's normal task creation, not expansion)
- Trivial tasks that are already well-specified
- Tasks already In Progress or beyond (expanding these risks changing intent mid-work)

## Workflow

### Step 1 — Read the Guides

Fetch the Backlog.md instruction guides before touching anything:

```
get_backlog_instructions (overview)
get_backlog_instructions (task-creation)
```

These define the required structure and constraints. Do not rely on memory.

### Step 2 — View the Target Task and Its Context

Call `task_view` on the target task. Then gather surrounding context:

- **Parent task** — if the task has a parent, view it to understand the broader goal and constraints
- **Dependencies** — view tasks listed in `Dependencies` to understand what feeds in
- **Dependents** — search/list for tasks that depend on this one to understand what downstream work expects
- **Milestone** — note the milestone; it frames scope and priority
- **Sibling subtasks** — view other subtasks under the same parent to understand the division of labor and avoid scope overlap

This context prevents expanding the task beyond its intended boundaries or duplicating sibling work.

### Step 3 — Explore the Codebase

The original task description is usually meager because the author had context the ticket doesn't capture. Explore the actual code to ground the expansion in reality:

- **Read the files the task names** — understand the existing patterns, types, and conventions
- **Search for related code** — grep/glob for the keywords, function names, or patterns the task mentions
- **Identify the consumer** — what downstream code will use the output of this task? What interfaces does it expect?
- **Find the authoritative sources** — SDK headers, config files, XML definitions, existing similar implementations
- **Note the gaps** — where does the existing code fall short of what the task needs? What's missing?

Document file paths, line numbers, type signatures, and patterns discovered. This becomes the "Background" and "Key Files to Reference" sections.

### Step 4 — Ask Clarifying Questions

Before expanding, identify ambiguities and ask the user. Use the `question` tool. Batch all questions in one round. Focus on:

- **Scope boundaries** — what's included vs excluded
- **Format preferences** — e.g., header-only vs header+cpp, table vs comments, enums vs #defines
- **Depth of inventory** — exhaustive vs representative, all panels vs one panel
- **Pairing requirements** — should related concepts (e.g., L:vars + events) be grouped together
- **Downstream consumer expectations** — what format does the next task in the chain need

Do NOT ask questions you could answer yourself by reading the code or the board. One round only.

### Step 5 — Write the Expanded Description

Structure the description with these sections (adapt as needed — not every task needs all of them):

#### Goal
1-3 sentences on what the task produces and why it matters. State the current pain (what's broken, missing, or fragmented) and the end state this task achieves.

#### Background — How X Works in This Codebase
Explain the mechanism the task touches, with code examples. A developer who has never seen this subsystem should understand the existing patterns after reading this section. Include:
- The relevant class/API and how it's used (with a short code snippet)
- The distinction from adjacent mechanisms that might be confused (e.g., "L:vars are NOT MODULE_VAR structs")
- The data flow: how does input arrive, how is state stored, how is output produced

#### Scope — What to Build
Break the deliverable into numbered subsections. For each:
- **Location** — exact file path(s) where the artifact goes
- **Format** — what the artifact looks like (with a code example showing the expected structure)
- **Content requirements** — what must be included, with specifics (e.g., "every var must have a comment documenting type, range, and physical name")
- **Organization** — how the content is structured (by subsystem, by panel, alphabetical, etc.)
- **Inclusion/exclusion rules** — what's in scope and what's explicitly excluded

#### What NOT to Do
A bulleted list of explicit boundaries. This is critical — it prevents scope creep and keeps the task atomic. Cover:
- Files that should NOT be modified (refactoring is a separate task)
- Adjacent features that belong to other tasks (name them by ID)
- Patterns/technologies that are forbidden (e.g., no std::string, no heap allocation)
- Integration steps that are out of scope (e.g., "do not add #include to existing files")

#### Dependencies
- **Blocking** — what tasks must complete before this one can start (or "None blocking" if it can start immediately)
- **Downstream** — what tasks depend on this one's output

#### Key Files to Reference
A bulleted list of files the developer should read, each with a one-line description of its role:
```
- `path/to/file.h` — Event IDs (authoritative control names)
- `path/to/file.xml` — L:var strings and types
```

### Step 6 — Write Acceptance Criteria

Acceptance criteria are testable, specific statements that verify the task is complete. Each should be a single verifiable assertion. Use `acceptanceCriteriaSet` to replace the task's criteria.

Rules:
- **Testable** — a reviewer can look at the output and say "yes" or "no" definitively
- **Specific** — name exact file paths, exact struct names, exact enum values
- **Cover edge cases** — ambiguous mappings, exclusion rules, compilation targets
- **Cover negative constraints** — "no X is created", "no existing files are modified"
- **NOT implementation steps** — avoid "implement helper function"; instead "the header defines enum X with values Y, Z"
- **Include build verification** — "compiles cleanly under [specific configuration]"

Aim for 10-20 criteria for a substantial task. Group them logically: file existence → content structure → content quality → negative constraints → compilation.

### Step 7 — Write Definition of Done

The DoD is a completion checklist (not acceptance criteria). It covers the mechanical and quality gates the developer must verify before declaring the task done. Use `definitionOfDoneAdd` to add items.

Cover:
- **File creation** — the files exist at the specified paths
- **Compilation** — builds cleanly under the target configuration(s)
- **Initialization** — all members/entries initialized (no uninitialized data)
- **Platform constraints** — no exceptions, no RTTI, no threads, no Win32 API (adapt to project)
- **Style** — formatted with the project's formatter (clang-format, prettier, etc.)
- **No forbidden patterns** — no std::string, no heap allocation, etc. (adapt to project)
- **Documentation** — cross-references documented, coverage verified
- **Verification** — every item in the source inventory is accounted for

Aim for 8-15 DoD items. These are checkboxes the developer ticks off, so keep each item a single actionable verification.

### Step 8 — Add References and Documentation

Use `task_edit` to attach:
- **references** — source files, SDK headers, XML definitions the developer must read
- **documentation** — supporting files that explain the patterns (e.g., the class header that defines the API being used)

These appear as structured fields on the task and give the developer one-click access to the key files.

### Step 9 — Verify and Report

After editing, call `task_view` on the task to verify the final state. Confirm:
- Description has all intended sections
- Acceptance criteria are present and testable
- DoD items are present and actionable
- References and documentation are attached

Report to the user: what sections were added, how many acceptance criteria, how many DoD items, and confirm the task is ready for handoff.

## Principles

### Self-Contained
A developer in a fresh context window should be able to pick up the task and start working without asking questions. The description, background, and key files provide everything needed.

### Grounded in Code
Every expansion is grounded in actual codebase exploration, not speculation. File paths, type names, patterns, and conventions are verified by reading the code.

### Boundaries Explicit
"What NOT to Do" is as important as "What to Build". Scope creep kills atomic tasks. Name the adjacent tasks that own the out-of-scope work.

### Testable Criteria
Acceptance criteria are verifiable assertions, not implementation steps. A reviewer checks them against the output, not against the process.

### Preserve Intent
Do not materially change the task's intent. Expand and clarify, but do not redirect. If the codebase exploration reveals the task's original scope was wrong, flag it to the user rather than silently changing it.

### One Round of Questions
Ask all clarifying questions in a single batch before expanding. Do not pepper the user with questions during the expansion. If new ambiguities arise during writing, make a reasonable choice and note it.

## Quick Reference — Tool Calls

```
# Step 1: Guides
get_backlog_instructions (overview)
get_backlog_instructions (task-creation)

# Step 2: Context
task_view (id: "TASK-X.Y")
task_view (id: "TASK-PARENT")
task_list (status: "To Do")  # find dependents

# Step 3: Codebase (use read, grep, glob tools)

# Step 4: Questions
question (questions: [...])

# Step 5-7: Edit the task
task_edit (
  id: "TASK-X.Y",
  description: "<full expanded description>",
  acceptanceCriteriaSet: [...],
  definitionOfDoneAdd: [...]
)

# Step 8: References
task_edit (
  id: "TASK-X.Y",
  references: [...],
  documentation: [...]
)

# Step 9: Verify
task_view (id: "TASK-X.Y")
```
