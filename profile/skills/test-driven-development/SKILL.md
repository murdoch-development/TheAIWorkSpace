---
name: test-driven-development
description: Run a Build-WS task through test-driven development by instructing its coder subagent to use observable red-green-refactor cycles. Attach this skill to a Build-WS session when TDD is desired; it does not replace Build-WS or create a separate implementation agent.
---

# Test-Driven Development for Build-WS

Continue to follow the normal Build-WS lifecycle, including task selection, worktree creation, coder delegation, review, and status transitions. Do not implement directly and do not spawn an additional coder.

When Build-WS launches its normal `coder` subagent, include the following TDD contract in the coder assignment. This is an explicit orchestrator instruction to write the tests required by the contract.

## Coder TDD Contract

For each smallest observable behavior that advances an acceptance criterion, use a **red → green → refactor** cycle:

1. **Red:** Before changing production behavior, write the narrowest useful test or executable example. Run it and confirm it fails because the behavior is missing or incorrect—not because of syntax, setup, environment, or an unrelated defect.
2. **Green:** Make the smallest production change that passes the focused test. Run the focused test and relevant nearby tests.
3. **Refactor:** Improve names, duplication, structure, and test clarity only while tests are green. Do not add new behavior during refactoring.
4. Repeat for the next behavior. Commit only a green state; do not commit a deliberately failing red state.

Select the cheapest test level that provides meaningful confidence:

- Unit tests for isolated decisions and transformations
- Integration or contract tests for persistence, protocols, boundaries, and wiring
- End-to-end tests only when the behavior cannot be proven more cheaply below the UI or system boundary

Test public behavior rather than private structure. Avoid assertions about internal call order or implementation details unless that interaction is itself the contract. Reuse the project's existing test framework and conventions; do not add a dependency solely to practice TDD.

For a bug, reproduce the defect with a failing regression test before fixing it. For risky legacy code without usable coverage, first add the narrowest characterization test needed to preserve existing behavior, then add the failing test for the requested change.

If a meaningful failing test cannot be written because a required contract, fixture, environment, or test seam is missing, stop and report the blocker to Build-WS rather than silently implementing first.

Do not manufacture low-value tests for documentation, generated output, formatting-only changes, static assets, or configuration with no executable behavior. Use the most direct existing validation instead, such as a parser, schema check, build, lint, established snapshot, or documented manual check. Record why TDD did not apply and what alternative evidence was used.

For every completed behavior, include concise evidence in task notes and the final coder report:

- Behavior exercised
- Red: focused command and expected failure observed
- Green: focused command and passing result
- Refactor performed, or `none`
- Final verification command and result

Do not weaken, delete, or rewrite a valid test merely to accommodate an implementation mistake. Change an expectation only when the task evidence or an approved clarification shows that the prior expectation was wrong.

## Build-WS Verification

When the coder returns, verify that its report contains TDD evidence or a justified proportional exception. If the coder implemented behavioral code without demonstrating red first, do not represent the work as TDD-compliant; return it for correction or report the deviation to the user according to the normal Build-WS workflow.
