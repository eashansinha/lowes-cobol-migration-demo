---
name: mfm-jira-board
description: Task-tracking protocol for COBOL/JCL work in this repo. The ticket is a Markdown task file under docs/tasks/ (or, once the Jira integration is enabled, an issue on the "Mainframe Modernization" MFM board). Use in every session that migrates, fixes or analyses a job - read the task first, log each phase, report only numbers you produced, and leave Verified/Done to humans.
---

# Task protocol (Markdown task file today, MFM Jira board once enabled)

The task is the source of truth for scope and acceptance criteria; the repo is
the source of truth for behaviour. When they disagree, write the disagreement
into the task - do not pick one silently.

Where the task lives:
- **Markdown** - `docs/tasks/<JOB>.md` (exemplar: `docs/tasks/GLPOST01.md`).
  Produced by an Ask Devin planning conversation; the same content is what
  goes into a Jira issue later.
- **Jira** (when connected) - board
  https://cog-gtm.atlassian.net/jira/software/projects/MFM/boards/2594, project
  `MFM`. Columns `Backlog -> Ready for Devin -> In Progress -> In Review ->
  Verified -> Done`. Devin owns `Ready for Devin -> In Progress -> In Review`
  only.

## 1. Before touching code

1. Read the whole task (Markdown file, or Jira issue + **all** comments).
   Extract: job/program, input and output DDs with layouts, the reproduction
   command, the proof required, values the task says will change, and every
   line marked "preserve".
2. If anything in that list is missing, ask once - as a `QUESTION -` line in
   the task file's `## Session log` (or a Jira comment) - then continue with
   whatever does not depend on the answer. Never invent a layout or a proof.
3. Log the start: session link + one-line plan. Jira: also move
   `Ready for Devin -> In Progress`. Read-only analysis: never transition.

## 2. During the work - one log entry per phase

Append to `## Session log` in the task file (or one Jira comment per phase).
First word is the phase so the log reads as a timeline:

```
BASELINE  - build + legacy run: MAXCC, record counts, comparator verdict on main
EXPLORE   - JCL steps, DD -> file -> copybook -> layouts/*.json, downstream jobs
IMPLEMENT - files added, build result (nothing under cobol/ jcl/ data/ layouts/ changed)
PARITY    - comparator tail per output file; every difference explained and
            classified fixed / approved deviation / blocker
VERIFY    - regression harness summary, return-code table, CI status
```

Rules:
- Every number you log came from a command you ran in this session. Never type
  an expected value.
- Cite `file:line` or paragraph names for every business rule you mention.
- Behaviour that looks wrong is a **finding**: log it as "observed behaviour:
  preserve" and reproduce it. It is not fixed in a migration; offer a separate
  task.
- Never edit, re-sort, trim or re-encode a baseline file to make a comparison
  pass. An unexplained difference is a blocker.

## 3. Finishing

1. Open the PR. Its body carries the PARITY and VERIFY evidence, pasted.
2. Log the PR URL, head SHA, CI status and the one-line verdict. Jira: move
   `In Progress -> In Review`.
3. Never mark the task Verified or Done, never edit the original task text
   above the session log, never create Jira issues outside `MFM`.
4. If blocked: log `BLOCKED -` with the diff or question and stop; leave the
   task In Progress.

## 4. Follow-ups

New instructions on the same task (a chat message, or an `@Devin` Jira comment
forwarded to this session) are scoped to that task. After any code change,
re-run the comparator and harness and log a fresh PARITY / VERIFY entry.
