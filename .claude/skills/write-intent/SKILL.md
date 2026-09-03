---
name: write-intent
description: Capture a change request as an intent artifact in intent/. Use
  when someone describes an idea, a problem to fix, or a change they want
  made, and the repo rule "start changes from an intent/ artifact" applies.
  Triggers on "write an intent", "new intent", "intent for <idea>",
  "start a change", or a change request with no intent artifact yet.
---
# Write an intent

Turn a conversation into a committed `intent/<slug>.md`, following the
AI-native SDLC Plan stage: the originator's idea, in the originator's own
terms, captured as a version-controlled artifact the next stage (Design →
`spec.md`) can act on.

## The template

Use `intent/TEMPLATE.md` verbatim — keep its section headings (Problem,
Proposed outcome, Affected users and systems, Constraints, Open questions,
Decisions). Read it before writing; its HTML comment lists the rules.

## Process

1. **Interview before writing.** Ask the questions an analyst would ask,
   one round at a time:
   - What can't you do today? Who is affected?
   - What does better look like — how would you know this worked?
   - What is explicitly *out* of scope?
   - What must keep working no matter what? (constraints)
   - What is undecided that someone else must decide? (open questions)
2. **Write in the originator's voice.** Copy their phrasing for the
   Problem section. Do not polish, formalize, or convert to user stories.
   If the originator says "cleanup takes forever", the intent says
   "cleanup takes forever", not "teardown latency exceeds acceptable
   thresholds".
3. **No solutions.** If the originator proposes an implementation, capture
   it as a proposed outcome or open question, not as the design. "How" is
   spec.md's and plan.md's job. If the repo already contains an obvious
   approach, mention it at most as a candidate open question.
4. **Open questions are the review agenda.** Surface every decision the
   originator can't make alone. Number them; mirror them in the Decisions
   table. Each will be answered in its own PR thread.
5. **Show, then correct.** Present the draft, ask the originator to fix
   anything misremembered, and only then write the file. Their
   corrections win over template wording.
6. **File as `intent/<short-slug>.md`** (kebab-case, e.g.
   `intent/aks-migration.md`), propose the commit and PR. The PR *is* the
   review venue: questions are answered in threads, approvals are
   recorded, and the merge is the gate into Design.
7. **Reference prior intents** if a similar one exists in `intent/` —
   link it, don't re-ask answered questions; carry the still-open ones
   forward.

## Scope guard

- Informational questions do not get an intent. If the request turns out
  to be a question ("how does X work?"), answer it and skip this skill.
- The intent is one artifact, one PR. Do not start Design (`spec.md`),
  do not touch code, do not open follow-up PRs.
- If the request is too small for an intent (typo fix, lint correction),
  say so and just do it.
