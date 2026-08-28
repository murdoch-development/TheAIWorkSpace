---
name: engineering-principles
description: Software Engineering Principles — SOLID, design principles, anti-patterns, code organization, testing, and lint rules. MANDATORY for all code production and review.
---

# Software Engineering Principles

These principles are requirements, not suggestions. Every line of code should be
evaluated against them before committing. This document is portable — place it in
any project's root or reference it from any AGENTS.md.

---

## SOLID Principles

- **Single Responsibility** — Every module, class, and function does one thing.
  If you can't describe what a file does in one sentence, it does too much.
  A service that handles payments should not also send emails.
  A function that calculates a fee should not also persist it.

- **Open/Closed** — Software entities should be open for extension, closed for modification.
  Add new behavior by adding new code — don't modify existing code to add a feature.
  When you find yourself editing a working function to support a new case, stop and extend instead.

- **Liskov Substitution** — Subtypes must be substitutable for their base types.
  If a function accepts an interface, any implementation of that interface must work.
  Consumers should not need to know which concrete type they received.

- **Interface Segregation** — Don't force consumers to depend on methods they don't use.
  A client that only reads data shouldn't expose write methods.
  Split large interfaces into focused, role-specific ones.

- **Dependency Inversion** — Depend on abstractions, not concretions.
  Use dependency injection over direct instantiation.
  High-level modules should not import low-level modules — both should depend on abstractions.

---

## Design Principles

- **DRY (Don't Repeat Yourself)** — Every piece of knowledge has a single, unambiguous
  representation. If you see the same logic in two places, extract it. Duplicated
  logic is duplicated bugs — fix one, forget the other.

- **KISS (Keep It Simple, Stupid)** — The simplest solution that works is the best solution.
  A 10-line function that's clear beats a 3-line function that's clever.
  Readability is a feature, not a luxury.

- **YAGNI (You Ain't Gonna Need It)** — Don't build for hypothetical future requirements.
  Build what's needed now. If you don't have two implementations of something,
  don't create an abstraction for it.

- **Separation of Concerns** — Each layer has a distinct responsibility.
  Configuration, business logic, entry points, and operational tooling should be
  clearly separated. Don't mix concerns across layers.

- **Composition over Inheritance** — Prefer composing small, focused units over
  deep class hierarchies. A module that combines a client + handler is better
  than a module that inherits from a base class.

- **Encapsulation** — Hide internal implementation details.
  Other modules shouldn't know how a service stores its data internally.
  If you change the internals, nothing outside should break.

- **Orthogonality** — Components should be independent. Changing one shouldn't
  require changes to another. If two modules always change together, they're
  not orthogonal — consider merging them.

- **Reversibility** — Design decisions that are easy to reverse.
  Prefer choices that can be undone. Avoid irreversible commitments when a
  reversible one works. A feature flag is reversible. A schema migration is not.

- **Boy Scout Rule** — Leave the code cleaner than you found it.
  If you touch a file, fix one small thing — a typo, a missing type, a stale comment.
  The codebase improves incrementally with every change.

- **Principle of Least Privilege** — A module should only access the data and
  capabilities it needs. A function that calculates a fee shouldn't have access
  to the database. Grant minimum access, not maximum convenience.

- **Single Source of Truth** — Every piece of knowledge has exactly one authoritative
  representation. Configuration, constants, business rules — define once, reference
  everywhere. If two places define the same thing, they will diverge.

- **Convention over Configuration** — Reduce the number of decisions developers need
  to make. Establish patterns and follow them. When the codebase has a convention,
  follow it — even if you'd do it differently.

- **Defensive Programming** — Validate inputs at boundaries. Assume external data is
  untrusted. Check invariants. Don't trust that callers follow the contract.
  Validate early, fail fast, and produce clear error messages.

---

## What NOT to Do

- **Don't add dependencies without justification.** Every dependency is a future migration.
  If a small utility function solves the problem, write it — don't install a library.

- **Don't catch errors you can't handle.** If a function throws and you can't recover,
  let it propagate. Catching and re-throwing with a different message is noise.

- **Don't use `any`.** TypeScript exists for a reason. If you need `any`, the type
  system is telling you something is wrong. Fix the type, don't silence the compiler.

- **Don't create abstractions for hypothetical future use.** Abstract when you have
  2+ implementations, not before. A generic interface with one implementation
  is premature abstraction.

- **Don't leave TODOs without a tracking issue.** Every TODO must reference an issue
  number or a documented decision. Untracked TODOs are untracked debt.

- **Don't skip tests for "simple" code.** Simple code is where bugs hide. If it's
  simple, the test is simple too — write it.

- **Don't commit code that doesn't pass the test suite.** The CI pipeline is the
  source of truth. If CI fails, fix it before committing.

- **Don't assume the network is reliable.** Every external call must handle failures
  gracefully. Timeouts, retries, and fallbacks are not optional.

- **Don't hardcode values that should be configurable.** URLs, ports, timeouts,
  retry counts — these belong in environment variables or config, not in source code.

- **Don't mix business logic with infrastructure.** A function that calculates
  a value should not also make HTTP calls. Separate calculation from communication.

- **Don't create God objects.** A class or module that knows too much or does too much
  is a maintenance nightmare. Split it into focused units.

- **Don't create circular dependencies.** Module A imports Module B, Module B imports
  Module A. Break the cycle by extracting a shared interface or restructuring.

- **Don't optimize prematurely.** Don't optimize until you've measured. The bottleneck
  is rarely where you think it is. Profile first, then optimize.

- **Don't nest deeply.** More than 3 levels of indentation is a code smell.
  Extract into functions. Use early returns to reduce nesting.

- **Don't use flag arguments.** A boolean parameter that changes the function's behavior
  is a code smell. Split into two functions with clear names.

- **Don't use magic strings.** Hardcoded strings that carry meaning should be
  constants or enums. `"APPLIED"` should be `TransactionStatus.APPLIED`.

- **Don't scatter conditionals.** The same `if` logic spread across multiple files
  is a maintenance hazard. Centralize the decision.

---

## Code Organization Rules

- **One concern per file.** If a file does two unrelated things, split it.

- **Imports at the top.** No inline imports except for dynamic imports in specific
  cases (e.g., avoiding circular dependencies).

- **No magic numbers.** `0.15` means nothing. Define a named constant.

- **Constants over inline values.** Define constants for repeated values.

- **Error messages must be actionable.** "Operation failed" is useless.
  "CreateTransaction failed: 400 insufficient funds" tells you exactly what went wrong.

- **Log what matters.** Log state transitions, external API calls, errors, and
  business decisions. Don't log routine operations.

- **Comments explain why, not what.** The code explains what it does.
  Comments explain why it does it that way.

---

## Testing Principles

- **Tests are documentation.** A test should explain what the code does.
  If you can't understand the code from its tests, the tests are wrong.

- **Fast, isolated, deterministic.** Tests must be fast (seconds, not minutes),
  isolated (no shared state), and deterministic (same result every time).

- **Test behavior, not implementation.** Test what the code does, not how it does it.
  If you refactor the implementation, the tests should still pass.

- **Unit tests for logic, integration tests for wiring.** Unit tests verify
  calculations and decisions. Integration tests verify that modules connect correctly.

- **Test the edges.** The most bugs live at boundaries — API calls, database queries,
  file I/O, user input. Test these first.

- **One assertion per concept.** A test can have multiple assertions, but they should
  all verify the same concept. If you're testing two things, write two tests.

---

## Lint Rules (ESLint)

These rules are enforced by the linter. Violations block commits.

| Rule | Threshold | Principle enforced |
|---|---|---|
| `no-explicit-any` | `error` | No `any` — fix the type, don't silence the compiler |
| `no-magic-numbers` | `error`, ignore `[0, 1, -1]` | Constants over inline values |
| `no-unused-vars` | `error` | DRY, no dead code |
| `explicit-function-return-type` | `error` | Explicit over implicit |
| `complexity` | `error`, 10 | Single Responsibility |
| `max-lines-per-function` | `error`, 80 | Single Responsibility, KISS |
| `max-depth` | `error`, 3 | KISS, reduce nesting |
| `max-params` | `error`, 4 | Interface Segregation |
| `naming-convention` | `error` | Convention over Configuration |
| `prevent-abbreviations` | `error` | Readability — full names for clarity |
| `no-nested-ternary` | `error` | KISS, readability |
| `no-array-reduce` | `error` | Readability |
| `no-null` | `off` | Allow null when needed |

---

## Adherence Checklist

Before completing your task, verify:

- [ ] **SOLID:** Does each module/function have one responsibility?
- [ ] **DRY:** Is there any duplicated logic?
- [ ] **KISS:** Is this the simplest solution that works?
- [ ] **YAGNI:** Am I building for a real need, not a hypothetical future?
- [ ] **Separation of Concerns:** Are layers properly separated?
- [ ] **No `any`:** Are all types explicit and correct?
- [ ] **No magic numbers/strings:** Are constants defined?
- [ ] **No deep nesting:** Is indentation <= 3 levels?
- [ ] **Error messages:** Are they actionable and descriptive?
- [ ] **Tests:** Does the code have appropriate test coverage?
- [ ] **No premature abstraction:** Are abstractions justified by 2+ implementations?
- [ ] **Boy Scout:** Did I leave the code cleaner than I found it?
