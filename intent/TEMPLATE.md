# Intent: <one-line title>

Author: <name (role)>. Status: draft.

<!--
Rules for filling this in (also enforced by the write-intent skill):
- Written in the originator's own terms. The reviewer edits meaning,
  not voice — if a sentence sounds like it came from an analyst, rewrite
  it back to what the originator said.
- Describes what is wanted, why, and under which constraints. Never
  prescribes a solution — "how" belongs in spec.md and plan.md.
- Sections below are the contract; keep the headings verbatim so later
  stages (and the write-intent skill) can parse them.
- Open questions are the review agenda: each is answered in its own PR
  thread, then the answer moves into the Decisions table.
-->

## Problem

What cannot be done today, who is affected, and what the pain costs.
Plain description, no solutioning.

## Proposed outcome

What the world looks like after this change, in observable terms. This
is the list a reviewer checks the eventual diff against.

## Affected users and systems

Users: who runs into the change.
Systems changed: files/dirs/services expected to be touched.
Systems unchanged: what is explicitly *not* touched (as important as
the first list — it bounds blast radius).

## Constraints

Hard boundaries the change must live inside: timeline, policies,
conventions that must be preserved, things that must keep working.

## Open questions

Numbered. Each one is a decision someone must make before or during
Design. Resolved in the PR thread, consolidated into the Decisions
table as they close.

## Decisions

| # | Question | Decision | Decided by | Date |
|---|----------|----------|------------|------|
| 1 | <mirror of open question 1> | open | | |
