---
name: write-intent
description: Capture a change request as a story issue on GitHub. Use when
  someone describes an idea, a problem to fix, or a change they want made,
  and the repo rule "start changes from an accepted story issue" applies.
  Triggers on "write an intent", "new story", "file a story", "intent for
  <idea>", "start a change", or a change request with no story issue yet.
---
# Write a story issue

Turn a conversation into a GitHub issue the Sponsor can accept at the
daily sync. The issue is the first artifact of the SDLC: the originator's
idea, in the originator's own words. Once accepted, it becomes the input
to `/speckit.specify`, which turns it into a spec on its own branch.

## The format

Four sections, matching `.github/ISSUE_TEMPLATE/story.md`:

- **Problem** — what can't be done today, who is affected, what it costs.
- **Outcome** — what you will be able to *see working* when it's done.
- **Out of scope** — what this story deliberately does not touch.
- **Must keep working** — what must not break.

No solutions, no technology choices — "how" belongs to `/speckit.plan`.

## Process

1. **Interview before writing.** Ask the questions an analyst would ask,
   one round at a time:
   - What can't you do today? Who is affected?
   - What does better look like — what would you show in a 2-minute demo?
   - What is explicitly *out* of scope?
   - What must keep working no matter what?
2. **Check the size.** A story must be finishable in **1–2 days,
   including real verification** (for this repo: the actual cloud or k3d
   run). The outcome is one thing; if you can't state it without "and"
   joining two outcomes, propose a split into a ladder of stories, MVP
   first, and file the first rung only.
3. **Write in the originator's voice.** Copy their phrasing for the
   Problem section. Do not polish, formalize, or convert to user
   stories. If the originator says "cleanup takes forever", the issue
   says "cleanup takes forever".
4. **Show, then file — with an explicit approval gate.** Present the full
   draft (title + all four sections) and ask for approval. Do **not**
   create the issue until the originator explicitly confirms ("post it",
   "looks good", "yes"). Silence, a new question, or a correction is not
   approval — apply corrections, re-show the draft, and wait again. Only
   after explicit confirmation, create the issue:

   ```
   gh issue create \
     --title "<one-line outcome>" \
     --label intent \
     --body-file <(cat <<'BODY'
   ### Problem
   ...
   ### Outcome
   ...
   ### Out of scope
   ...
   ### Must keep working
   ...
   BODY
   )
   ```

   If `gh` is unavailable or unauthenticated, output the title and body
   as a block the originator can paste into a new issue, and say so —
   do not silently fall back to writing a file.
5. **Stop there.** Acceptance is the Sponsor's call at the daily sync
   (they apply the `intent:accepted` label and the roles are assigned). Do not
   run `/speckit.specify`, do not touch code, do not open a branch.
6. **Link prior stories** if a related issue exists — reference it in
   the body rather than re-asking answered questions.

## Scope guard

- Informational questions do not get a story. If the request turns out
  to be a question ("how does X work?"), answer it and skip this skill.
- If the request is too small for a story (typo fix, lint correction),
  say so and just do it.
